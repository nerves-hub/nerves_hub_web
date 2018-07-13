defmodule NervesHubWeb.ProductControllerTest do
  use NervesHubWeb.ConnCase.Browser

  alias NervesHub.Fixtures
  alias NervesHub.Products

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: nil}

  def fixture(:product) do
    {:ok, product} = Products.create_product(@create_attrs)
    product
  end

  describe "index" do
    test "lists all products", %{conn: conn} do
      conn = get(conn, product_path(conn, :index))
      assert html_response(conn, 200) =~ "Listing Products"
    end
  end

  describe "new product" do
    test "renders form", %{conn: conn} do
      conn = get(conn, product_path(conn, :new))
      assert html_response(conn, 200) =~ "New Product"
    end
  end

  describe "create product" do
    test "redirects to show when data is valid", %{conn: conn, current_tenant: tenant} do
      conn = post(conn, product_path(conn, :create), product: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == product_path(conn, :show, id)

      conn = get(conn, product_path(conn, :show, id))
      assert html_response(conn, 200) =~ "Show Product"
      assert html_response(conn, 200) =~ tenant.name
      assert html_response(conn, 200) =~ product_device_path(conn, :new, id)
      assert html_response(conn, 200) =~ product_device_path(conn, :index, id)
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, product_path(conn, :create), product: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Product"
    end
  end

  describe "edit product" do
    setup [:create_product]

    test "renders form for editing chosen product", %{conn: conn, product: product} do
      conn = get(conn, product_path(conn, :edit, product))
      assert html_response(conn, 200) =~ "Edit Product"
    end
  end

  describe "update product" do
    setup [:create_product]

    test "redirects when data is valid", %{conn: conn, product: product} do
      conn = put(conn, product_path(conn, :update, product), product: @update_attrs)
      assert redirected_to(conn) == product_path(conn, :show, product)

      conn = get(conn, product_path(conn, :show, product))
      assert html_response(conn, 200) =~ "some updated name"
    end

    test "renders errors when data is invalid", %{conn: conn, product: product} do
      conn = put(conn, product_path(conn, :update, product), product: @invalid_attrs)
      assert html_response(conn, 200) =~ "Edit Product"
    end
  end

  describe "delete product" do
    setup [:create_product]

    test "deletes chosen product", %{conn: conn, product: product} do
      conn = delete(conn, product_path(conn, :delete, product))
      assert redirected_to(conn) == product_path(conn, :index)

      assert_error_sent(404, fn ->
        get(conn, product_path(conn, :show, product))
      end)
    end
  end

  defp create_product(_) do
    tenant = Fixtures.tenant_fixture()
    product = Fixtures.product_fixture(tenant)
    {:ok, product: product, tenant: tenant}
  end
end
