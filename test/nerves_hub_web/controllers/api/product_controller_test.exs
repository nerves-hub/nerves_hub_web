defmodule NervesHubWeb.API.ProductControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Fixtures

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
      conn = get(conn, Routes.api_product_path(conn, :index, org.name))
      assert json_response(conn, 403)["status"] != ""
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

      Accounts.add_org_user(org, user, %{role: :admin})

      conn = post(conn, Routes.api_product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org read", %{user2: user, conn2: conn, org: org} do
      name = "test"
      product = %{name: name}

      Accounts.add_org_user(org, user, %{role: :view})

      conn = post(conn, Routes.api_product_path(conn, :create, org.name), product)
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))

      assert response(conn, 403)
    end

    test "product delete with associated firmwares", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      # Create firmware for product
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      Fixtures.device_fixture(org, product, firmware)

      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))

      assert response(conn, 409)
    end
  end

  describe "delete product roles" do
    setup [:create_product]

    test "ok: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :admin})

      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      conn = get(conn, Routes.api_product_path(conn, :show, org.name, product.name))

      assert response(conn, 403)
    end

    test "error: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :view})

      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert json_response(conn, 403)["status"] != ""
    end

    test "error: org read", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :view})

      conn = delete(conn, Routes.api_product_path(conn, :delete, org.name, product.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  defp create_product(%{user: user, org: org}) do
    product = Fixtures.product_fixture(user, org, %{name: "api"})
    {:ok, %{product: product}}
  end
end
