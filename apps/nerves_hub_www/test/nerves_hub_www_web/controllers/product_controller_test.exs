defmodule NervesHubWWWWeb.ProductControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.{Fixtures, Products}

  @create_attrs %{name: "some name"}
  @update_attrs %{delta_updatable: false}
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
      assert html_response(conn, 200) =~ "Create Product"
    end
  end

  describe "create product" do
    test "redirects to show when data is valid", %{conn: conn, org: org} do
      params = @create_attrs
      conn = post(conn, Routes.product_path(conn, :create, org.name), product: params)
      assert redirected_to(conn) == Routes.device_path(conn, :index, org.name, params.name)

      conn = get(conn, Routes.product_path(conn, :show, org.name, params.name))
      assert html_response(conn, 200) =~ "Show Product"
      assert html_response(conn, 200) =~ org.name
      assert html_response(conn, 200) =~ Routes.firmware_path(conn, :index, org.name, params.name)
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.product_path(conn, :create, org.name), product: @invalid_attrs)
      assert html_response(conn, 200) =~ "Create Product"
    end
  end

  describe "update product" do
    test "redirects to show when data is valid", %{
      conn: conn,
      fixture: %{product: product},
      org: org
    } do
      params = @update_attrs

      conn =
        put(conn, Routes.product_path(conn, :update, org.name, product.name), product: params)

      assert redirected_to(conn) == Routes.device_path(conn, :index, org.name, product.name)
      assert %{delta_updatable: false} = Products.get_product!(product.id)
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

    test "error when product has associated firmwares and devices", %{
      conn: conn,
      org: org,
      product: product
    } do
      # Create a firmware for the product
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      Fixtures.device_fixture(org, product, firmware)
      redirect_path = Routes.product_path(conn, :index, org.name)

      do_delete = fn ->
        conn
        |> Plug.Conn.put_req_header("referer", redirect_path)
        |> delete(Routes.product_path(conn, :delete, org.name, product.name))
      end

      result = do_delete.()
      assert redirected_to(result) == redirect_path
      assert get_flash(result, :error) =~ "Product has associated firmwares"

      NervesHubWebCore.Firmwares.delete_firmware(firmware)
      result = do_delete.()
      assert redirected_to(result) == redirect_path
      assert get_flash(result, :error) =~ "Product has associated devices"
    end
  end

  defp create_product(%{user: user, org: org}) do
    product = Fixtures.product_fixture(user, org)
    [product: product]
  end
end
