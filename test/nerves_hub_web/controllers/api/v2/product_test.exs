defmodule NervesHubWeb.API.V2.ProductTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  describe "index" do
    test "lists products", %{conn: conn, product: product} do
      conn = get(conn, "/api/v2/products")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert product.name in names
    end
  end

  describe "create" do
    test "creates a product", %{conn: conn, org: org} do
      conn =
        post(conn, "/api/v2/products", %{
          "data" => %{
            "type" => "product",
            "attributes" => %{
              "name" => "AshCreated",
              "org_id" => org.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["name"] == "AshCreated"
    end
  end

  describe "show" do
    test "returns a product by id", %{conn: conn, product: product} do
      conn = get(conn, "/api/v2/products/#{product.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == product.name
    end
  end

  describe "list_by_org" do
    test "lists products by org", %{conn: conn, org: org, product: product} do
      conn = get(conn, "/api/v2/products/by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      names = Enum.map(resp["data"], & &1["attributes"]["name"])
      assert product.name in names
    end
  end

  describe "get_by_org_and_name" do
    test "returns a product by org and name", %{conn: conn, org: org, product: product} do
      conn = get(conn, "/api/v2/products/by-org/#{org.id}/by-name/#{product.name}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["name"] == product.name
    end
  end

  describe "delete" do
    test "soft-deletes a product", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org, %{name: "ToDelete"})

      conn = delete(conn, "/api/v2/products/#{product.id}")
      assert response(conn, 200)
    end
  end
end
