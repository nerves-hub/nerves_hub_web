defmodule NervesHubWWWWeb.ProductControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  @create_attrs %{name: "some name"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all products", %{conn: conn, org: org} do
      conn = get(conn, Routes.product_path(conn, :index, org.name))
      assert html_response(conn, 200) =~ "Products"
    end
  end

  describe "new product" do
    test "renders form", %{conn: conn, org: org} do
      conn = get(conn, Routes.product_path(conn, :new, org.name))
      assert html_response(conn, 200) =~ "Create a Product"
    end
  end

  describe "create product" do
    test "redirects to show when data is valid", %{conn: conn, org: org} do
      params = @create_attrs
      conn = post(conn, Routes.product_path(conn, :create, org.name), product: params)
      assert %{product_name: product_name} = redirected_params(conn)
      assert redirected_to(conn) == Routes.product_path(conn, :show, org.name, params.name)

      conn = get(conn, Routes.product_path(conn, :show, org.name, params.name))
      assert html_response(conn, 200) =~ "Show Product"
      assert html_response(conn, 200) =~ org.name
      assert html_response(conn, 200) =~ Routes.firmware_path(conn, :index, org.name, params.name)
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.product_path(conn, :create, org.name), product: @invalid_attrs)
      assert html_response(conn, 200) =~ "Create a Product"
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, org: org, product: product} do
      path = Routes.product_path(conn, :delete, org.name, product.name)
      conn = delete(conn, path)
      assert redirected_to(conn) == Routes.product_path(conn, :index, org.name)
      conn = get(conn, path)
      assert html_response(conn, 404)
    end

    test "error when product has associated firmwares", %{
      conn: conn,
      org: org,
      product: product
    } do
      # Create a firmware for the product
      org_key = Fixtures.org_key_fixture(org)
      Fixtures.firmware_fixture(org_key, product)

      conn = delete(conn, Routes.product_path(conn, :delete, org.name, product.name))

      assert redirected_to(conn) == Routes.product_path(conn, :index, org.name)
      assert get_flash(conn, :error) =~ "Product has associated firmwares"
    end
  end

  defp create_product(%{user: user, org: org}) do
    product = Fixtures.product_fixture(user, org)
    [product: product]
  end
end
