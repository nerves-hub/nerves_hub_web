defmodule NervesHubAPIWeb.ProductControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.Fixtures
  alias NervesHubWebCore.{Accounts, Products}

  setup context do
    org = Fixtures.org_fixture(context.user, %{name: "api test"})
    Map.put(context, :org, org)
  end

  describe "index" do
    test "lists all products", %{conn: conn, org: org} do
      conn = get(conn, Routes.product_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "index roles" do
    test "error: missing org read", %{conn2: conn, org: org} do
      conn = get(conn, Routes.product_path(conn, :index, org.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "create products" do
    test "renders product when data is valid", %{conn: conn, org: org} do
      name = "test"
      product = %{name: name}

      conn = post(conn, Routes.product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.product_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "create products roles" do
    test "ok: org write", %{user2: user, conn2: conn, org: org} do
      name = "test"
      product = %{name: name}

      Accounts.add_org_user(org, user, %{role: :write})

      conn = post(conn, Routes.product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "error: org read", %{user2: user, conn2: conn, org: org} do
      name = "test"
      product = %{name: name}

      Accounts.add_org_user(org, user, %{role: :read})

      conn = post(conn, Routes.product_path(conn, :create, org.name), product)
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      conn = get(conn, Routes.product_path(conn, :show, org.name, product.name))

      assert response(conn, 403)
    end

    test "product delete with associated firmwares", %{
      conn: conn,
      org: org,
      product: product
    } do
      # Create firmware for product
      org_key = Fixtures.org_key_fixture(org)
      Fixtures.firmware_fixture(org_key, product)

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))

      assert response(conn, 409)
    end
  end

  describe "delete product roles" do
    setup [:create_product]

    test "ok: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :delete})

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      conn = get(conn, Routes.product_path(conn, :show, org.name, product.name))

      assert response(conn, 403)
    end

    test "error: org delete", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :read})

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))
      assert json_response(conn, 403)["status"] != ""
    end

    test "error: org read", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :read})

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  describe "update product" do
    setup [:create_product]

    test "renders deployment when data is valid", %{conn: conn, org: org, product: product} do
      conn =
        put(conn, Routes.product_path(conn, :update, org.name, product.name),
          product: %{"name" => "new"}
        )

      assert %{"name" => "new"} = json_response(conn, 200)["data"]

      path = Routes.product_path(conn, :show, org.name, "new")
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["name"] == "new"
    end
  end

  describe "update product roles" do
    setup [:create_product]

    test "ok: org write", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :write})
      Products.add_product_user(product, user, %{role: :admin})

      conn =
        put(conn, Routes.product_path(conn, :update, org.name, product.name),
          product: %{"name" => "new"}
        )

      assert %{"name" => "new"} = json_response(conn, 200)["data"]

      path = Routes.product_path(conn, :show, org.name, "new")
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["name"] == "new"
    end

    test "error: org read", %{user2: user, conn2: conn, org: org, product: product} do
      Accounts.add_org_user(org, user, %{role: :read})

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))
      assert json_response(conn, 403)["status"] != ""
    end
  end

  defp create_product(%{user: user, org: org}) do
    product = Fixtures.product_fixture(user, org, %{name: "api"})
    {:ok, %{product: product}}
  end
end
