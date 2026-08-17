defmodule NervesHubWeb.API.IrohEndpointControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Devices
  alias NervesHub.Devices.NetworkIdentities
  alias NervesHub.Fixtures

  @endpoint_id "c8924b6c9b7a8528b1365ebec4b2e43b6edebef684f8521f12b8caaf6e1b2302"
  @other_id String.duplicate("ab", 32)
  @unowned_id String.duplicate("cd", 32)

  describe "index" do
    test "is empty for an organization holding none", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert json_response(conn, 200)["data"] == []
    end

    test "lists an endpoint with what holds it", %{conn: conn, org: org} do
      {:ok, _} = NetworkIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert [endpoint] = json_response(conn, 200)["data"]
      assert endpoint["identifier"] == @endpoint_id
      assert endpoint["service"] == "iroh"
      assert endpoint["instance"] == "default"
      # Registered by hand, so nothing has proven it and nobody in the
      # organization holds it.
      assert endpoint["source"] == "operator"
      assert endpoint["owner"]["type"] == "none"
    end

    test "names the device holding one it reported", %{conn: conn, org: org, product: product} do
      device = device_fixture(org, product)
      {:ok, _} = NetworkIdentities.report(device.id, "iroh", %{identifier: @endpoint_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert [%{"owner" => owner, "source" => "device_reported"}] = json_response(conn, 200)["data"]

      assert owner == %{
               "type" => "device",
               "device_identifier" => device.identifier,
               "user_name" => nil,
               "user_email" => nil
             }
    end

    test "does not list another organization's endpoints", %{conn: conn, org: org, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "SomeoneElse"})
      {:ok, _} = NetworkIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert json_response(conn, 200)["data"] == []
    end

    test "lists only iroh, not every service the table holds", %{conn: conn, org: org, product: product} do
      device = device_fixture(org, product)
      {:ok, _} = NetworkIdentities.report(device.id, "iroh", %{identifier: @endpoint_id})
      {:ok, _} = NetworkIdentities.report(device.id, "tailscale", %{identifier: @other_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert [%{"identifier" => @endpoint_id}] = json_response(conn, 200)["data"]
    end
  end

  describe "index filters" do
    setup %{conn: conn, org: org, product: product, user: user} do
      device = device_fixture(org, product)
      {:ok, _} = NetworkIdentities.report(device.id, "iroh", %{identifier: @endpoint_id})

      {:ok, _} =
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{
          "identifier" => @other_id,
          "user_email" => user.email
        })
        |> json_response(201)
        |> then(&{:ok, &1})

      {:ok, _} = NetworkIdentities.register(org.id, :iroh, %{identifier: @unowned_id})

      [device: device]
    end

    defp identifiers(conn), do: for(e <- json_response(conn, 200)["data"], do: e["identifier"])

    test "unfiltered lists all three", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name))

      assert length(identifiers(conn)) == 3
    end

    test "narrows to endpoints a device holds", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "device"))

      assert identifiers(conn) == [@endpoint_id]
    end

    test "narrows to endpoints a person holds", %{conn: conn, org: org} do
      # The filter value is the one `owner.type` renders, not the context's
      # `org_user` — a caller should not need a second vocabulary.
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "user"))

      assert identifiers(conn) == [@other_id]
    end

    test "narrows to endpoints nothing in the organization holds", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "none"))

      assert identifiers(conn) == [@unowned_id]
    end

    test "refuses an owner that is not one of the three", %{conn: conn, org: org} do
      # Ignoring it would answer a typo with the whole list, which reads as a
      # filter that matched everything.
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "operator"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "device, user, none"
    end

    test "matches the start of an endpoint id", %{conn: conn, org: org} do
      conn =
        get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, search: String.slice(@endpoint_id, 0, 8)))

      assert identifiers(conn) == [@endpoint_id]
    end

    test "does not match the middle of an endpoint id", %{conn: conn, org: org} do
      # Prefix, not substring: what a caller has is the truncated front of a key.
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, search: String.slice(@endpoint_id, 20, 8)))

      assert identifiers(conn) == []
    end

    test "matches a device identifier", %{conn: conn, org: org, device: device} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, search: device.identifier))

      assert identifiers(conn) == [@endpoint_id]
    end

    test "matches a member's name", %{conn: conn, org: org, user: user} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, search: user.name))

      assert identifiers(conn) == [@other_id]
    end

    test "combines owner and search", %{conn: conn, org: org} do
      conn =
        get(
          conn,
          Routes.api_iroh_endpoint_path(conn, :index, org.name,
            owner: "device",
            search: String.slice(@endpoint_id, 0, 8)
          )
        )

      assert identifiers(conn) == [@endpoint_id]

      conn =
        get(
          conn,
          Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "user", search: String.slice(@endpoint_id, 0, 8))
        )

      assert identifiers(conn) == []
    end

    test "blank filters are no filters", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :index, org.name, owner: "", search: ""))

      assert length(identifiers(conn)) == 3
    end
  end

  describe "create" do
    test "registers an endpoint against the organization", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{"identifier" => @endpoint_id})

      assert %{"data" => endpoint} = json_response(conn, 201)
      assert endpoint["identifier"] == @endpoint_id
      assert endpoint["source"] == "operator"
      assert endpoint["owner"]["type"] == "none"

      assert {:ok, %{org_id: org_id, owner: "org"}} =
               NetworkIdentities.get_owner_by_identifier(:iroh, @endpoint_id)

      assert org_id == org.id
    end

    test "points location at the endpoint it made", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{"identifier" => @endpoint_id})

      assert [location] = get_resp_header(conn, "location")
      assert location == Routes.api_iroh_endpoint_path(conn, :show, org.name, @endpoint_id)
    end

    test "attaches it to a member by their email", %{conn: conn, org: org, user: user} do
      conn =
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{
          "identifier" => @endpoint_id,
          "user_email" => user.email
        })

      assert %{"data" => %{"owner" => owner}} = json_response(conn, 201)

      # Read back from the association rather than from what register/3 returned,
      # which is the bug this asserts against: an unloaded owner renders as none.
      assert owner["type"] == "user"
      assert owner["user_email"] == user.email
      assert owner["user_name"] == user.name

      assert {:ok, %{owner: "org_user", user_id: user_id}} =
               NetworkIdentities.get_owner_by_identifier(:iroh, @endpoint_id)

      assert user_id == user.id
    end

    test "takes an instance for a second endpoint on one owner", %{conn: conn, org: org} do
      conn =
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{
          "identifier" => @endpoint_id,
          "instance" => "console"
        })

      assert json_response(conn, 201)["data"]["instance"] == "console"
    end

    test "refuses a key registered elsewhere, without saying where", %{conn: conn, org: org, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "AlreadyHasIt"})
      {:ok, _} = NetworkIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      conn = post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{"identifier" => @endpoint_id})

      # 409 rather than 422: the request is well formed, the key is taken.
      detail = json_response(conn, 409)["errors"]["detail"]
      assert detail =~ "already registered"
      assert detail =~ "claimed the next time that device connects"
      refute detail =~ "AlreadyHasIt"
    end

    test "refuses an email that is not a member of this organization", %{conn: conn, org: org} do
      outsider = Fixtures.user_fixture(%{email: "outsider@example.com"})

      conn =
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{
          "identifier" => @endpoint_id,
          "user_email" => outsider.email
        })

      assert json_response(conn, 422)["errors"]["detail"] =~ "not belong to a member"
    end

    test "gives the same answer for an address with no account", %{conn: conn, org: org} do
      # Otherwise this endpoint reports which addresses have accounts, to anyone
      # who can register a key.
      conn =
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{
          "identifier" => @endpoint_id,
          "user_email" => "nobody@example.com"
        })

      assert json_response(conn, 422)["errors"]["detail"] =~ "not belong to a member"
    end

    test "rejects a missing identifier", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{})

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "show" do
    test "finds one by its key", %{conn: conn, org: org} do
      {:ok, _} = NetworkIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :show, org.name, @endpoint_id))

      assert json_response(conn, 200)["data"]["identifier"] == @endpoint_id
    end

    test "404s for a key nobody holds", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :show, org.name, @endpoint_id))

      assert json_response(conn, 404)
    end

    test "404s for one held by another organization", %{conn: conn, org: org, user: user} do
      # A key is not a secret — it is the one thing an outsider is most likely
      # to have — so knowing one must not read another organization's record.
      other_org = Fixtures.org_fixture(user, %{name: "NotYours"})
      {:ok, _} = NetworkIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      conn = get(conn, Routes.api_iroh_endpoint_path(conn, :show, org.name, @endpoint_id))

      assert json_response(conn, 404)
    end
  end

  describe "delete" do
    test "removes one, and then it is gone", %{conn: conn, org: org} do
      {:ok, _} = NetworkIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})

      conn = delete(conn, Routes.api_iroh_endpoint_path(conn, :delete, org.name, @endpoint_id))
      assert response(conn, 204)

      assert {:error, :not_found} = NetworkIdentities.get_owner_by_identifier(:iroh, @endpoint_id)
    end

    test "404s for a key nobody holds", %{conn: conn, org: org} do
      conn = delete(conn, Routes.api_iroh_endpoint_path(conn, :delete, org.name, @endpoint_id))

      assert json_response(conn, 404)
    end

    test "will not remove another organization's", %{conn: conn, org: org, user: user} do
      other_org = Fixtures.org_fixture(user, %{name: "StillNotYours"})
      {:ok, _} = NetworkIdentities.register(other_org.id, :iroh, %{identifier: @endpoint_id})

      conn = delete(conn, Routes.api_iroh_endpoint_path(conn, :delete, org.name, @endpoint_id))

      assert json_response(conn, 404)
      assert {:ok, _} = NetworkIdentities.get_owner_by_identifier(:iroh, @endpoint_id)
    end
  end

  describe "roles" do
    test "a view-only member may read but not register", %{conn: conn, org: org, user: user} do
      org_user = NervesHub.Repo.get_by!(OrgUser, org_id: org.id, user_id: user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      assert conn |> get(Routes.api_iroh_endpoint_path(conn, :index, org.name)) |> json_response(200)

      assert_error_sent(401, fn ->
        post(conn, Routes.api_iroh_endpoint_path(conn, :create, org.name), %{"identifier" => @endpoint_id})
      end)
    end

    test "a view-only member may not delete", %{conn: conn, org: org, user: user} do
      {:ok, _} = NetworkIdentities.register(org.id, :iroh, %{identifier: @endpoint_id})
      org_user = NervesHub.Repo.get_by!(OrgUser, org_id: org.id, user_id: user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      assert_error_sent(401, fn ->
        delete(conn, Routes.api_iroh_endpoint_path(conn, :delete, org.name, @endpoint_id))
      end)

      assert {:ok, _} = NetworkIdentities.get_owner_by_identifier(:iroh, @endpoint_id)
    end
  end

  defp device_fixture(org, product) do
    {:ok, device} =
      Devices.create_device(%{
        identifier: "device-#{System.unique_integer([:positive])}",
        org_id: org.id,
        product_id: product.id
      })

    device
  end
end
