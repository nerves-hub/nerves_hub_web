defmodule NervesHubWWWWeb.ProductControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.Fixtures

  @create_attrs %{name: "some name"}
  @invalid_attrs %{name: nil}

  describe "index" do
    test "lists all products", %{conn: conn} do
      conn = get(conn, product_path(conn, :index))
      assert html_response(conn, 200) =~ "All Products"
    end
  end

  describe "new product" do
    test "renders form", %{conn: conn} do
      conn = get(conn, product_path(conn, :new))
      assert html_response(conn, 200) =~ "Create a Product"
    end
  end

  describe "create product" do
    test "redirects to show when data is valid", %{conn: conn, current_org: org} do
      conn = post(conn, product_path(conn, :create), product: @create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == product_path(conn, :show, id)

      conn = get(conn, product_path(conn, :show, id))
      assert html_response(conn, 200) =~ "Show Product"
      assert html_response(conn, 200) =~ org.name
      assert html_response(conn, 200) =~ product_firmware_path(conn, :index, id)
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, product_path(conn, :create), product: @invalid_attrs)
      assert html_response(conn, 200) =~ "Create a Product"
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
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    {:ok, product: product, org: org}
  end
end
