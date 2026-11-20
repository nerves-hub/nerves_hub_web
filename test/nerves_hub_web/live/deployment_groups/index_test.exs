defmodule NervesHubWeb.Live.DeploymentGroups.IndexTest do
  # Approving, skipping and retrying a step go through the workflow code,
  # which the other workflow tests run synchronously too.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices
  alias NervesHub.Devices.Deployments
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Repo

  @workflow %{
    "version" => 1,
    "steps" => [
      %{
        "name" => "Canary",
        "matching_conditions" => %{"tags" => ["canary"]},
        "failure_tolerance" => %{"devices" => 1}
      },
      %{"name" => "Sign-off", "type" => "approval_required"}
    ]
  }

  defp groups_path(org, product), do: "/org/#{org.name}/#{product.name}/deployment_groups"

  # A group whose current release walks @workflow.
  defp workflow_group(%{user: user, org_key: org_key, product: product, tmp_dir: tmp_dir}) do
    firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.0.0", dir: tmp_dir})

    group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, name: "Workflow Group", user: user})
    {:ok, group} = ManagedDeployments.update_deployment_group(group, %{workflow_definition: @workflow}, user)

    next_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "1.1.0", dir: tmp_dir})

    {:ok, {release, _}} =
      ManagedDeployments.create_deployment_release(group, next_firmware, nil, user, %{}, broadcast: false)

    [canary, sign_off, _catch_all] = Workflows.release_steps(release.id)

    %{workflow_group: group, canary: canary, sign_off: sign_off}
  end

  # The canary step is done and the sign-off waits for someone.
  defp await_sign_off(%{workflow_group: group, canary: canary, sign_off: sign_off}) do
    canary |> Ecto.Changeset.change(status: :completed) |> Repo.update!()
    {:ok, sign_off} = Workflows.start_step(group, sign_off)

    %{sign_off: sign_off}
  end

  # The canary step went over its failure limit.
  defp stop_canary(%{workflow_group: group, canary: canary}) do
    {:ok, canary} = Workflows.start_step(group, canary)

    %{canary: canary |> Ecto.Changeset.change(status: :error) |> Repo.update!()}
  end

  test "a product with no groups shows how to make one", %{conn: conn, user: user, org: org} do
    product = Fixtures.product_fixture(user, org, %{name: "Spaghetti"})

    conn
    |> visit(groups_path(org, product))
    |> assert_has("#deployment-groups-empty h2", text: "Make your first deployment group")
    |> assert_has("#deployment-groups-empty a", text: "Upload firmware")
    |> assert_has("#deployment-groups-empty a", text: "New deployment group")
    |> refute_has("#needs-you")
    |> refute_has("#deployment-group-filters")
  end

  test "a group that needs nothing runs on its own", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: group
  } do
    conn
    |> visit(groups_path(org, product))
    |> assert_has("h1", text: "Deployment groups")
    |> assert_has("span", text: "1 group · 0 devices")
    |> assert_has("#needs-you", text: "Nothing needs you.")
    |> assert_has("#group-#{group.id} a", text: group.name)
    |> assert_has("#group-#{group.id}", text: "Paused")
    |> assert_has("#group-#{group.id}", text: "Sends nothing until resumed")
  end

  test "device counts leave out deleted devices", %{
    conn: conn,
    org: org,
    product: product,
    deployment_group: group,
    device: device
  } do
    device = Deployments.update_deployment_group(device, group)

    conn
    |> visit(groups_path(org, product))
    |> assert_has("#group-#{group.id}", text: "1 device")

    {:ok, _} = Devices.delete_device(device)

    conn
    |> visit(groups_path(org, product))
    |> assert_has("#group-#{group.id}", text: "0 devices")
  end

  test "says how many devices no group reaches", %{conn: conn, org: org, product: product} do
    conn
    |> visit(groups_path(org, product))
    |> assert_has("a[href$='devices?deployment_id=-1']", text: "1 device")
    |> assert_has("p", text: "isn’t in any group, so no release reaches it.")
  end

  test "the grid view is remembered", %{
    conn: conn,
    org: org,
    product: product,
    user: user,
    deployment_group: group
  } do
    conn
    |> visit(groups_path(org, product))
    |> assert_has("button[aria-label='List'][aria-pressed='true']")
    |> assert_has("#group-#{group.id}")
    |> unwrap(&(&1 |> element("button[aria-label='Grid']") |> render_click()))
    |> assert_has("button[aria-label='Grid'][aria-pressed='true']")
    |> assert_has("#group-card-#{group.id}", text: group.name)
    |> refute_has("#group-#{group.id}")

    assert Repo.reload(user).display_preferences.deployment_group_view == :grid

    conn
    |> visit(groups_path(org, product))
    |> assert_has("#group-card-#{group.id}")
  end

  describe "search and filters" do
    test "search matches names, tags and firmware versions, in any case", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: group
    } do
      for search <- [String.upcase(group.name), "BETA-EDGE", "1.0"] do
        conn
        |> visit(groups_path(org, product) <> "?" <> URI.encode_query(search: search))
        |> assert_has("#group-#{group.id}")
      end
    end

    test "a search that matches nothing says so and can be cleared", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: group
    } do
      conn
      |> visit(groups_path(org, product))
      |> fill_in("Search deployment groups", with: "nothing like it")
      |> assert_has("#deployment-groups-no-matches", text: "No groups match “nothing like it”")
      |> refute_has("#group-#{group.id}")
      |> refute_has("#needs-you")
      |> click_button("Clear search")
      |> assert_path(groups_path(org, product))
      |> assert_has("#group-#{group.id}")
    end

    test "filters on platform and firmware version", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: group
    } do
      conn
      |> visit(groups_path(org, product) <> "?platform=platform&firmware=1.0.0")
      |> assert_has("#group-#{group.id}")

      conn
      |> visit(groups_path(org, product) <> "?platform=elsewhere")
      |> assert_has("#deployment-groups-no-matches", text: "No groups match these filters")
      |> refute_has("#group-#{group.id}")
      |> click_button("Clear filters")
      |> assert_has("#group-#{group.id}")

      conn
      |> visit(groups_path(org, product) <> "?firmware=9.9.9")
      |> refute_has("#group-#{group.id}")
    end
  end

  describe "a step waiting for approval" do
    setup [:workflow_group, :await_sign_off]

    test "puts its group under Needs you", %{conn: conn, org: org, product: product, workflow_group: group} do
      conn
      |> visit(groups_path(org, product))
      |> assert_has("#needs-you-#{group.id}", text: "Awaiting approval")
      |> assert_has("#needs-you-#{group.id}", text: "Approving Sign-off lets the release carry on.")
      |> assert_has("#needs-you-#{group.id} button", text: "Approve and continue")
      |> refute_has("#group-#{group.id}")
    end

    test "is approved once the dialog is confirmed", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      workflow_group: group,
      sign_off: sign_off
    } do
      conn
      |> visit(groups_path(org, product))
      |> within("#needs-you-#{group.id}", &click_button(&1, "Approve and continue"))
      |> assert_has("#approve-step h2", text: "Approve Sign-off for Workflow Group?")

      refute Repo.reload(sign_off).approved_at

      conn
      |> visit(groups_path(org, product))
      |> within("#needs-you-#{group.id}", &click_button(&1, "Approve and continue"))
      |> within("#approve-step", &click_button(&1, "Approve and continue"))
      |> assert_has("div", text: "Sign-off approved.")
      |> refute_has("#approve-step")
      |> refute_has("#needs-you-#{group.id}")

      approved = Repo.reload(sign_off)

      assert approved.approved_by_id == user.id
      assert approved.approved_at
    end

    test "a step approved elsewhere since the page loaded is left alone", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      workflow_group: group,
      sign_off: sign_off
    } do
      session =
        conn
        |> visit(groups_path(org, product))
        |> within("#needs-you-#{group.id}", &click_button(&1, "Approve and continue"))

      {:ok, _} = Workflows.approve_step(group, sign_off, user)

      session
      |> within("#approve-step", &click_button(&1, "Approve and continue"))
      |> assert_has("div", text: "Workflow Group has moved on since the page loaded. Nothing was changed.")
    end
  end

  describe "a step stopped on failures" do
    setup [:workflow_group, :stop_canary]

    test "puts its group under Needs you", %{conn: conn, org: org, product: product, workflow_group: group} do
      conn
      |> visit(groups_path(org, product))
      |> assert_has("#needs-you-#{group.id}", text: "Stopped")
      |> assert_has("#needs-you-#{group.id}", text: "stopped at Canary.")
      |> assert_has("#needs-you-#{group.id} button", text: "Skip step")
      |> assert_has("#needs-you-#{group.id} button", text: "Retry step")
    end

    test "counts the waiting devices, except on the phone's line beside the step", %{
      conn: conn,
      org: org,
      product: product,
      workflow_group: group,
      device: device
    } do
      Deployments.update_deployment_group(device, group)

      conn
      |> visit(groups_path(org, product))
      |> assert_has("#needs-you-#{group.id} span", text: "0 updated · 1 waiting", exact: true)
      |> assert_has("#needs-you-#{group.id} span", text: "0 updated", exact: true)
    end

    test "is skipped once the dialog is confirmed", %{
      conn: conn,
      org: org,
      product: product,
      workflow_group: group,
      canary: canary
    } do
      conn
      |> visit(groups_path(org, product))
      |> within("#needs-you-#{group.id}", &click_button(&1, "Skip step"))
      |> assert_has("#skip-step h2", text: "Skip Canary for Workflow Group?")
      |> assert_has("#skip-step", text: "moves on to Sign-off without Canary finishing.")
      |> within("#skip-step", &click_button(&1, "Skip step"))
      |> assert_has("div", text: "Canary skipped.")

      assert Repo.reload(canary).status == :skipped
    end

    test "is retried straight away", %{conn: conn, org: org, product: product, workflow_group: group, canary: canary} do
      conn
      |> visit(groups_path(org, product))
      |> within("#needs-you-#{group.id}", &click_button(&1, "Retry step"))
      |> assert_has("div", text: "Canary restarted.")
      |> refute_has("#needs-you-#{group.id}")

      assert Repo.reload(canary).status == :in_progress
    end
  end

  describe "a member with the view role" do
    setup [:workflow_group, :await_sign_off]

    setup do
      Repo.update_all(OrgUser, set: [role: :view])
      :ok
    end

    test "sees what is held but not the buttons that move it on", %{
      conn: conn,
      org: org,
      product: product,
      workflow_group: group
    } do
      conn
      |> visit(groups_path(org, product))
      |> assert_has("#needs-you-#{group.id}", text: "Awaiting approval")
      |> refute_has("button", text: "Approve and continue")
      |> refute_has("a", text: "New deployment group")
    end

    test "can't approve a step", %{conn: conn, org: org, product: product, workflow_group: group, sign_off: sign_off} do
      for event <- ["approve", "confirm-approve"] do
        session = visit(conn, groups_path(org, product))

        assert_unauthorized(fn -> render_click(session.view, event, %{"id" => to_string(group.id)}) end)
      end

      refute Repo.reload(sign_off).approved_at
    end
  end

  defp assert_unauthorized(fun) do
    Process.flag(:trap_exit, true)

    assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} = catch_exit(fun.())
  end
end
