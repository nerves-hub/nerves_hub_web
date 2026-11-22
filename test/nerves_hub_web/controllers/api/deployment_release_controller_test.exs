defmodule NervesHubWeb.API.DeploymentReleaseControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products.ApiKeys

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})
    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.1", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})

    %{org_key: org_key, firmware: firmware, next_firmware: next_firmware, deployment_group: deployment_group}
  end

  describe "index" do
    test "lists the group's releases, newest first", context do
      %{conn: conn, user: user, firmware: firmware, next_firmware: next_firmware} = context
      add_release(context, next_firmware, %{"description" => "the fix"})

      assert [newest, first] = json_response(get(conn, releases_path(context)), 200)["data"]

      assert %{
               "number" => 2,
               "firmware" => %{"uuid" => uuid, "version" => "1.0.1", "platform" => _, "architecture" => _},
               "archive_uuid" => nil,
               "required" => false,
               "description" => "the fix",
               "notes" => nil,
               "connecting_code" => nil,
               "connecting_code_mode" => "last",
               "delta_status" => "ready",
               "is_current" => true,
               "created_by" => %{"type" => "user", "name" => name, "email" => email},
               "inserted_at" => _,
               "updated_at" => _
             } = newest

      assert uuid == next_firmware.uuid
      assert name == user.name
      assert email == user.email

      assert %{"number" => 1, "is_current" => false} = first
      assert first["firmware"]["uuid"] == firmware.uuid
    end

    test "is open to a member who can only view", context do
      %{conn2: conn2, user2: user2, org: org} = context
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})

      assert [%{"number" => 1}] = json_response(get(conn2, releases_path(context)), 200)["data"]
    end

    test "is not found for a group that doesn't exist", %{conn: conn} = context do
      assert json_response(get(conn, releases_path(context, "missing")), 404)
    end
  end

  describe "show" do
    test "shows a release by its number", context do
      %{conn: conn, next_firmware: next_firmware} = context
      add_release(context, next_firmware, %{"connecting_code" => "IO.puts(:hi)", "connecting_code_mode" => "first"})

      assert %{
               "number" => 2,
               "connecting_code" => "IO.puts(:hi)",
               "connecting_code_mode" => "first",
               "is_current" => true
             } = json_response(get(conn, release_path(context, 2)), 200)["data"]

      assert %{"number" => 1, "is_current" => false} = json_response(get(conn, release_path(context, 1)), 200)["data"]
    end

    test "names the API key that made a release", context do
      %{conn: conn, product: product, user: user, deployment_group: deployment_group, next_firmware: next_firmware} =
        context

      api_key = Fixtures.api_key_fixture(product, user, %{"name" => "CI"})

      {:ok, _} =
        ManagedDeployments.create_deployment_release(deployment_group, next_firmware, nil, api_key, %{})

      assert %{"created_by" => %{"type" => "api_key", "name" => "CI"} = created_by} =
               json_response(get(conn, release_path(context, 2)), 200)["data"]

      refute Map.has_key?(created_by, "email")
    end

    test "is not found for a release the group doesn't have", %{conn: conn} = context do
      assert json_response(get(conn, release_path(context, 2)), 404)
      assert json_response(get(conn, release_path(context, "first")), 404)
    end

    test "is not found for a group that doesn't exist", %{conn: conn} = context do
      assert json_response(get(conn, release_path(context, 1, "missing")), 404)
    end
  end

  describe "create" do
    test "makes a release the group's current one", context do
      %{conn: conn, deployment_group: deployment_group, next_firmware: next_firmware} = context

      conn =
        post_json(conn, releases_path(context), %{
          "firmware" => next_firmware.uuid,
          "required" => true,
          "description" => "the fix",
          "notes" => "after the field test",
          "connecting_code" => "IO.puts(:hi)",
          "connecting_code_mode" => "override"
        })

      assert %{
               "number" => 2,
               "required" => true,
               "description" => "the fix",
               "notes" => "after the field test",
               "connecting_code" => "IO.puts(:hi)",
               "connecting_code_mode" => "override",
               "is_current" => true,
               "created_by" => %{"type" => "user"}
             } = json_response(conn, 201)["data"]

      assert get_resp_header(conn, "location") == [release_path(context, 2)]

      {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group.id)
      assert deployment_group.current_release.firmware_id == next_firmware.id
      assert deployment_group.current_release.connecting_code == "IO.puts(:hi)"

      assert Enum.any?(AuditLogs.logs_for(deployment_group), &(&1.description =~ "created a new release"))
    end

    test "takes an archive", context do
      %{conn: conn, org_key: org_key, product: product, next_firmware: next_firmware, tmp_dir: tmp_dir} = context
      archive = Fixtures.archive_fixture(org_key, product, %{dir: tmp_dir})

      conn = post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid, "archive" => archive.uuid})

      assert json_response(conn, 201)["data"]["archive_uuid"] == archive.uuid
    end

    test "refuses a release with the current release's firmware and archive", context do
      %{conn: conn, firmware: firmware} = context

      conn = post_json(conn, releases_path(context), %{"firmware" => firmware.uuid})

      assert json_response(conn, 422)["errors"] == %{
               "firmware" => ["The current release already has this firmware and archive"]
             }
    end

    test "refuses firmware or an archive the product doesn't have", context do
      %{conn: conn, next_firmware: next_firmware} = context
      missing = "00000000-0000-0000-0000-000000000000"

      conn1 = post_json(conn, releases_path(context), %{"firmware" => missing})
      assert json_response(conn1, 422)["errors"] == %{"firmware" => ["does not exist"]}

      conn2 = post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid, "archive" => missing})
      assert json_response(conn2, 422)["errors"] == %{"archive" => ["does not exist"]}

      conn3 = post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid, "archive" => "not-a-uuid"})
      assert json_response(conn3, 422)["errors"] == %{"archive" => ["does not exist"]}

      assert [%{number: 1}] = ManagedDeployments.list_deployment_releases(context.deployment_group)
    end

    test "needs firmware", %{conn: conn} = context do
      conn1 = post_json(conn, releases_path(context), %{"description" => "nothing"})
      assert json_response(conn1, 422)["errors"] == %{"firmware" => ["can't be blank"]}

      conn2 = post_json(conn, releases_path(context), %{"firmware" => ""})
      assert json_response(conn2, 422)["errors"] == %{"firmware" => ["can't be blank"]}
    end

    test "takes an empty archive as none", context do
      %{conn: conn, next_firmware: next_firmware} = context

      conn = post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid, "archive" => ""})

      assert %{"archive_uuid" => nil} = json_response(conn, 201)["data"]
    end

    test "refuses an unknown connecting code mode", context do
      %{conn: conn, next_firmware: next_firmware} = context

      conn =
        post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid, "connecting_code_mode" => "never"})

      assert json_response(conn, 422)["errors"] == %{"connecting_code_mode" => ["is invalid"]}
    end

    test "is not found for a group that doesn't exist", context do
      %{conn: conn, next_firmware: next_firmware} = context
      conn = post_json(conn, releases_path(context, "missing"), %{"firmware" => next_firmware.uuid})
      assert json_response(conn, 404)
    end

    test "needs deployment_group:update", context do
      %{conn2: conn2, user2: user2, org: org, next_firmware: next_firmware} = context
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn ->
        post_json(conn2, releases_path(context), %{"firmware" => next_firmware.uuid})
      end)
      |> assert_authorization_error(401)

      assert [%{number: 1}] = ManagedDeployments.list_deployment_releases(context.deployment_group)
    end

    test "works with a product API key, and records it", context do
      %{product: product, user: user, deployment_group: deployment_group, next_firmware: next_firmware} = context
      {conn, api_key} = key_conn(product, user, "manage")

      conn = post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid})

      assert %{"created_by" => %{"type" => "api_key", "name" => "CI"}} = json_response(conn, 201)["data"]

      assert [release | _] = ManagedDeployments.list_deployment_releases(deployment_group)
      assert release.created_by_api_key_id == api_key.id
      assert [log] = AuditLogs.logs_by(api_key)
      assert log.description =~ "API key CI created a new release"
    end

    test "refuses a product API key that can only view", context do
      %{product: product, user: user, next_firmware: next_firmware} = context
      {conn, _api_key} = key_conn(product, user, "view")

      assert_error_sent(401, fn ->
        post_json(conn, releases_path(context), %{"firmware" => next_firmware.uuid})
      end)
      |> assert_authorization_error(401)
    end
  end

  describe "update" do
    setup context do
      %{release: add_release(context, context.next_firmware, %{"description" => "the fix"})}
    end

    test "changes required and the connecting code, auditing each", context do
      %{conn: conn, deployment_group: deployment_group} = context
      before = AuditLogs.logs_for(deployment_group)

      conn =
        patch_json(conn, release_path(context, 1), %{
          "required" => true,
          "connecting_code" => "IO.puts(:hi)",
          "connecting_code_mode" => "first"
        })

      assert %{
               "number" => 1,
               "required" => true,
               "connecting_code" => "IO.puts(:hi)",
               "connecting_code_mode" => "first",
               "is_current" => false
             } = json_response(conn, 200)["data"]

      descriptions = Enum.map(AuditLogs.logs_for(deployment_group) -- before, & &1.description)
      assert Enum.any?(descriptions, &(&1 =~ "marked release 1 as required"))
      assert Enum.any?(descriptions, &(&1 =~ "changed the connecting code for release 1"))
    end

    test "leaves out what a release can't change once it's made", context do
      %{conn: conn, firmware: firmware, release: release} = context

      conn =
        patch_json(conn, release_path(context, release.number), %{
          "firmware" => firmware.uuid,
          "description" => "rewritten",
          "required" => true
        })

      assert %{"required" => true, "description" => "the fix", "firmware" => %{"version" => "1.0.1"}} =
               json_response(conn, 200)["data"]
    end

    test "removes the connecting code given null", context do
      %{conn: conn, release: release} = context
      {:ok, _} = ManagedDeployments.update_deployment_release(release, %{"connecting_code" => "old"}, context.user)

      conn = patch_json(conn, release_path(context, release.number), %{"connecting_code" => nil})

      assert %{"connecting_code" => nil} = json_response(conn, 200)["data"]
    end

    test "refuses an unknown connecting code mode", %{conn: conn, release: release} = context do
      conn = patch_json(conn, release_path(context, release.number), %{"connecting_code_mode" => "never"})
      assert json_response(conn, 422)["errors"] == %{"connecting_code_mode" => ["is invalid"]}
    end

    test "is not found for a release the group doesn't have", %{conn: conn} = context do
      assert json_response(patch_json(conn, release_path(context, 9), %{"required" => true}), 404)
    end

    test "is not found for a group that doesn't exist", %{conn: conn} = context do
      assert json_response(patch_json(conn, release_path(context, 1, "missing"), %{"required" => true}), 404)
    end

    test "needs deployment_group:update", context do
      %{conn2: conn2, user2: user2, org: org, release: release} = context
      {:ok, _} = Accounts.add_org_user(org, user2, %{role: :view})

      assert_error_sent(401, fn ->
        patch_json(conn2, release_path(context, release.number), %{"required" => true})
      end)
      |> assert_authorization_error(401)
    end

    test "works with a product API key, and audits it", context do
      %{product: product, user: user, release: release} = context
      {conn, api_key} = key_conn(product, user, "manage")

      conn =
        patch_json(conn, release_path(context, release.number), %{"required" => true, "connecting_code" => "hi"})

      assert %{"required" => true, "connecting_code" => "hi"} = json_response(conn, 200)["data"]

      descriptions = Enum.map(AuditLogs.logs_by(api_key), & &1.description)
      assert Enum.any?(descriptions, &(&1 =~ "API key CI marked release #{release.number} as required"))
      assert Enum.any?(descriptions, &(&1 =~ "API key CI changed the connecting code for release #{release.number}"))
    end
  end

  describe "a role limited to tagged devices" do
    # Such a role can't hold `deployment_group:update`, so it's the reads,
    # open to any member, that `require_every_device` closes.
    test "can't list or read a group's releases", %{conn2: conn2, org: org, user2: user2} = context do
      role = Fixtures.org_role_fixture(org, %{device_tags: ["support"], permissions: ["device:update"]})
      {:ok, _} = Accounts.add_org_user(org, user2, %{org_role_id: role.id})

      for path <- [releases_path(context), release_path(context, 1)] do
        assert_error_sent(401, fn -> get(conn2, path) end)
        |> assert_authorization_error(401)
      end
    end
  end

  defp add_release(%{deployment_group: deployment_group, user: user}, firmware, params) do
    {:ok, {release, _deployment_group}} =
      ManagedDeployments.create_deployment_release(deployment_group, firmware, nil, user, params)

    release
  end

  defp key_conn(product, user, role) do
    {:ok, api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => role})
    {build_auth_conn(token), api_key}
  end

  defp releases_path(%{org: org, product: product, deployment_group: deployment_group}, name \\ nil) do
    Routes.api_deployment_release_path(
      NervesHubWeb.Endpoint,
      :index,
      org.name,
      product.name,
      name || deployment_group.name
    )
  end

  defp release_path(%{org: org, product: product, deployment_group: deployment_group}, number, name \\ nil) do
    Routes.api_deployment_release_path(
      NervesHubWeb.Endpoint,
      :show,
      org.name,
      product.name,
      name || deployment_group.name,
      number
    )
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, JSON.encode!(body))
  end

  defp patch_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> patch(path, JSON.encode!(body))
  end
end
