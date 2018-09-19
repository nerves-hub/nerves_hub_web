defmodule NervesHubAPIWeb.ProductControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Accounts

  setup context do
    org = Fixtures.org_fixture(%{name: "api-test"})
    Accounts.add_user_to_org(context.user, org)
    Map.put(context, :org, org)
  end

  describe "index" do
    test "lists all products", %{conn: conn, org: org} do
      conn = get(conn, product_path(conn, :index, org.name))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create products" do
    test "renders product when data is valid", %{conn: conn, org: org} do
      name = "test"
      product = %{name: name}

      conn = post(conn, product_path(conn, :create, org.name), product)
      assert json_response(conn, 201)["data"]

      conn = get(conn, product_path(conn, :show, org.name, product.name))
      assert json_response(conn, 200)["data"]["name"] == name
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, product_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      conn = delete(conn, product_path(conn, :delete, org.name, product.name))
      assert response(conn, 204)

      conn = get(conn, product_path(conn, :show, org.name, product.name))

      assert response(conn, 403)
    end
  end

  describe "update product" do
    setup [:create_product]

    test "renders deployment when data is valid", %{conn: conn, org: org, product: product} do
      conn =
        put(
          conn,
          product_path(conn, :update, org.name, product.name),
          product: %{"name" => "new"}
        )

      assert %{"name" => "new"} = json_response(conn, 200)["data"]

      path = product_path(conn, :show, org.name, "new")
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["name"] == "new"
    end
  end

  defp create_product(%{org: org}) do
    product = Fixtures.product_fixture(org, %{name: "api"})
    {:ok, %{product: product}}
  end
end
