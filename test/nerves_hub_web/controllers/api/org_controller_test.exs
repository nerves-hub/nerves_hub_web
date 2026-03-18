defmodule NervesHubWeb.API.OrgControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures

  describe "index" do
    test "lists orgs for authenticated user", %{conn: conn, org: org} do
      conn = get(conn, Routes.api_org_path(conn, :index))
      assert %{"data" => [%{"name" => name}]} = json_response(conn, 200)
      assert name == org.name
    end

    test "does not include orgs the user is not a member of", %{conn2: conn} do
      conn = get(conn, Routes.api_org_path(conn, :index))
      assert %{"data" => data} = json_response(conn, 200)
      assert data == []
    end

    test "does not include products by default", %{conn: conn} do
      conn = get(conn, Routes.api_org_path(conn, :index))
      assert %{"data" => [org_data]} = json_response(conn, 200)
      refute Map.has_key?(org_data, "products")
    end

    test "includes products when include=products", %{conn: conn, org: org, user: user} do
      Fixtures.product_fixture(user, org, %{name: "included_product"})

      conn = get(conn, Routes.api_org_path(conn, :index, include: "products"))
      assert %{"data" => [org_data]} = json_response(conn, 200)
      assert is_list(org_data["products"])

      product_names = Enum.map(org_data["products"], & &1["name"])
      assert "included_product" in product_names
    end

    test "ignores invalid include values", %{conn: conn} do
      conn = get(conn, Routes.api_org_path(conn, :index, include: "invalid"))
      assert %{"data" => [org_data]} = json_response(conn, 200)
      refute Map.has_key?(org_data, "products")
    end
  end
end
