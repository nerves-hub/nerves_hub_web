defmodule NervesHubWeb.API.ProductControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHub.Products.ApiKeys
  alias NervesHub.Repo

  setup context do
    org = Fixtures.org_fixture(context.user, %{name: "api_test"})
    Map.put(context, :org, org)
  end

  describe "index" do
    test "lists all products", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_product_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index roles" do
    test "error: missing org read", %{conn2: conn, org: org} do
      assert_raise(Ecto.NoResultsError, fn ->
        get(conn, Routes.api_product_path(conn, :index, org.name))
      end)
    end
  end

  describe "create products" do
    test "renders product when data is valid", %{conn: conn, org: org} do
      name = "test"
      product = %{name: name}

      conn = post(conn, Routes.api_product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.api_product_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create products roles" do
    test "ok: org manage", %{user2: user, conn2: conn, org: org} do
      name = "test"
      product = %{name: name}

      Accounts.add_org_user(org, user, %{role: :manage})

      conn = post(conn, Routes.api_product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org read", %{user2: user, conn2: conn, org: org} do
      name = "test"
      product = %{name: name}

      Accounts.add_org_user(org, user, %{role: :view})

      assert_error_sent(401, fn ->
        post(conn, Routes.api_product_path(conn, :create, org.name), product)
      end)
      |> assert_authorization_error()
    end
  end

  describe "utilization" do
    setup [:create_product]

    test "reports the product's score, device authentication and items", %{conn: conn, org: org, product: product} do
      conn = get(conn, ~p"/api/orgs/#{org.name}/products/#{product.name}/utilization")

      assert %{"score" => score, "device_auth" => device_auth, "items" => items} = json_response(conn, 200)["data"]

      assert %{"done" => done, "total" => 13} = score
      assert done == Enum.count(items, &(&1["group"] != "optional" and &1["status"] == "done"))

      assert [
               %{"key" => "shared_secret", "label" => "Shared Secret", "level" => "warning", "devices" => 0},
               %{"key" => "local_cert", "label" => "LocalCert", "level" => "good", "devices" => 0},
               %{"key" => "nerves_key", "label" => "NervesKey", "level" => "good", "devices" => 0}
             ] = device_auth

      assert %{
               "key" => "device_auth",
               "group" => "authentication",
               "title" => "Device authentication",
               "status" => "todo",
               "summary" => "No device has connected yet.",
               "docs_url" => "https://docs.nerves-hub.org/auth/device-certificates"
             } = hd(items)

      assert Enum.any?(items, &(&1["group"] == "optional"))
    end

    test "leaves the organization's own items out for a product API key", context do
      %{org: org, product: product, user: user} = context
      {:ok, _api_key, token} = ApiKeys.create(product, user, %{"name" => "CI", "role" => "view"})

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "token #{token}")
        |> get(~p"/api/orgs/#{org.name}/products/#{product.name}/utilization")

      assert %{"score" => %{"total" => 12}, "items" => items} = json_response(conn, 200)["data"]

      keys = Enum.map(items, & &1["key"])
      refute "two_factor" in keys
      refute "custom_roles" in keys
      assert "ci_api_key" in keys
    end

    test "is refused to someone outside the organization", %{conn2: conn, org: org, product: product} do
      assert_raise(Ecto.NoResultsError, fn ->
        get(conn, ~p"/api/orgs/#{org.name}/products/#{product.name}/utilization")
      end)
    end
  end

  describe "show" do
    setup [:create_product]

    test "includes the product's settings", %{conn: conn, org: org, product: product} do
      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))

      assert json_response(conn, 200)["data"] == %{
               "name" => product.name,
               "require_unique_firmware_version" => true,
               "allowed_update_tools" => ["fwup"],
               "allow_unsigned_esp_idf_firmware" => false,
               "allow_unsigned_atomvm_firmware" => false,
               "default_managed_updates_allowed" => false
             }
    end
  end

  describe "update product" do
    setup [:create_product]

    test "updates the settings that were sent, and only those", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn =
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          allowed_update_tools: ["fwup", "esp-idf"]
        })

      assert json_response(conn, 200)["data"]["allowed_update_tools"] == ["fwup", "esp-idf"]

      product = Repo.reload(product)
      assert product.allowed_update_tools == ["fwup", "esp-idf"]
      # Untouched by a request that did not mention it.
      assert product.require_unique_firmware_version
      refute product.allow_unsigned_esp_idf_firmware
    end

    test "accepts a patch as well as a put", %{conn: conn, org: org, product: product} do
      conn =
        patch(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          require_unique_firmware_version: false
        })

      assert json_response(conn, 200)["data"]["require_unique_firmware_version"] == false
      refute Repo.reload(product).require_unique_firmware_version
    end

    test "sets the grant new devices start with", %{conn: conn, org: org, product: product} do
      conn =
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          default_managed_updates_allowed: true
        })

      assert json_response(conn, 200)["data"]["default_managed_updates_allowed"] == true
      assert Repo.reload(product).default_managed_updates_allowed
    end

    test "rejects an unknown update tool", %{conn: conn, org: org, product: product} do
      conn =
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          allowed_update_tools: ["fwup", "wat"]
        })

      assert json_response(conn, 422)["errors"]["allowed_update_tools"] == [
               "unknown update tool(s): wat"
             ]
    end

    # Silently ignoring these would report success for a request that changed
    # nothing — a rename in particular looks like it worked.
    test "refuses fields it cannot set rather than dropping them", %{
      conn: conn,
      org: org,
      product: product
    } do
      conn =
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          name: "renamed",
          org_id: 1
        })

      assert json_response(conn, 422)["errors"]["detail"] =~ ~s("name")
      assert json_response(conn, 422)["errors"]["detail"] =~ ~s("org_id")
      assert Repo.reload(product).name == product.name
    end
  end

  describe "update product roles" do
    setup [:create_product]

    test "ok: org manage", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :manage})

      conn =
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          allow_unsigned_esp_idf_firmware: true
        })

      assert json_response(conn, 200)["data"]["allow_unsigned_esp_idf_firmware"] == true
    end

    test "error: org view", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :view})

      assert_error_sent(401, fn ->
        put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
          allow_unsigned_esp_idf_firmware: true
        })
      end)
      |> assert_authorization_error()

      refute Repo.reload(product).allow_unsigned_esp_idf_firmware
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, Routes.api_product_path(conn, :show, org.name, product.name))
      end)
      |> assert_authorization_error(404)
    end
  end

  describe "delete product roles" do
    setup [:create_product]

    test "ok: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :manage})

      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      assert_error_sent(404, fn ->
        get(conn, Routes.api_product_path(conn, :show, org.name, product.name))
      end)
      |> assert_authorization_error(404)
    end

    test "error: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :view})

      assert_error_sent(401, fn ->
        delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      end)
      |> assert_authorization_error()
    end
  end

  defp create_product(%{user: user, org: org}) do
    product =
      Fixtures.product_fixture(user, org, %{name: "api", require_unique_firmware_version: true})

    {:ok, %{product: product}}
  end
end

defmodule NervesHubWeb.API.ProductControllerPlatformGateTest do
  # Not async: the platform gate is global application state, and flipping it
  # while another suite is uploading firmware would change that suite's answer.
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Repo

  test "a product cannot list a tool the instance has not enabled", %{conn: conn, user: user} do
    Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true) end)

    org = Fixtures.org_fixture(user, %{name: "api_gate_test"})
    product = Fixtures.product_fixture(user, org, %{name: "api"})

    conn =
      put(conn, Routes.api_product_path(conn, :update, org.name, product.name), %{
        allowed_update_tools: ["fwup", "esp-idf"]
      })

    assert json_response(conn, 422)["errors"]["allowed_update_tools"] == [
             "not enabled on NervesHub: esp-idf"
           ]

    assert Repo.reload(product).allowed_update_tools == ["fwup"]
  end
end
