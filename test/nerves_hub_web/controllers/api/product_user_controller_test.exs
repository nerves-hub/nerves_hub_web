defmodule NervesHubWeb.API.ProductUserControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products

  setup context do
    org = Fixtures.org_fixture(context.user, %{name: "api_test"})
    product = Fixtures.product_fixture(context.user, org, %{name: "api"})

    context
    |> Map.put(:org, org)
    |> Map.put(:product, product)
  end

  describe "index" do
    test "lists all product_users", %{conn: conn, org: org, user: user, product: product} do
      conn = get(conn, Routes.product_user_path(conn, :index, org.name, product.name))

      assert json_response(conn, 200)["data"] ==
               [%{"email" => user.email, "role" => "admin", "username" => user.username}]
    end
  end

  describe "index roles" do
    for role <- [:delete, :write, :read] do
      @role role

      test "error: product #{@role}", %{conn2: conn, org: org, user2: user, product: product} do
        Products.add_product_user(product, user, %{role: @role})
        conn = get(conn, Routes.product_user_path(conn, :index, org.name, product.name))
        assert json_response(conn, 403)["status"] != ""
      end
    end
  end

  describe "add product_users" do
    test "renders product_user when data is valid", %{
      conn: conn,
      org: org,
      user2: user2,
      product: product
    } do
      product_user = %{"username" => user2.username, "role" => "write"}

      conn =
        post(conn, Routes.product_user_path(conn, :add, org.name, product.name), product_user)

      assert json_response(conn, 201)["data"]

      conn =
        get(conn, Routes.product_user_path(conn, :show, org.name, product.name, user2.username))

      assert json_response(conn, 200)["data"]["username"] == user2.username
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      org: org,
      user2: user2,
      product: product
    } do
      product_user = %{"username" => user2.username, "role" => "bogus"}

      conn =
        post(conn, Routes.product_user_path(conn, :add, org.name, product.name), product_user)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "add role" do
    for role <- [:delete, :write, :read] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user, product: product} do
        Products.add_product_user(product, user, %{role: @role})
        product_user = %{"username" => user.username, "role" => "write"}

        conn =
          post(conn, Routes.product_user_path(conn, :add, org.name, product.name), product_user)

        assert json_response(conn, 403)["status"] != ""
      end
    end
  end

  describe "remove product_user" do
    setup [:create_product_user]

    test "remove existing user", %{conn: conn, org: org, user2: user, product: product} do
      conn =
        delete(
          conn,
          Routes.product_user_path(conn, :remove, org.name, product.name, user.username)
        )

      assert response(conn, 204)

      conn =
        get(conn, Routes.product_user_path(conn, :show, org.name, product.name, user.username))

      assert response(conn, 404)
    end
  end

  describe "remove role" do
    for role <- [:delete, :write, :read] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user, product: product} do
        Products.add_product_user(product, user, %{role: @role})

        conn =
          delete(conn, Routes.product_user_path(conn, :remove, org.name, product.name, "1234"))

        assert json_response(conn, 403)["status"] != ""
      end
    end
  end

  describe "update product_user role" do
    setup [:create_product_user]

    test "renders product_user when data is valid", %{
      conn: conn,
      org: org,
      user2: user,
      product: product
    } do
      conn =
        put(conn, Routes.product_user_path(conn, :update, org.name, product.name, user.username),
          role: "write"
        )

      assert json_response(conn, 200)["data"]["role"] == "write"

      path = Routes.product_user_path(conn, :show, org.name, product.name, user.username)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"]["role"] == "write"
    end
  end

  describe "update role" do
    for role <- [:delete, :write, :read] do
      @role role

      test "error: org #{@role}", %{conn2: conn, org: org, user2: user, product: product} do
        Products.add_product_user(product, user, %{role: @role})

        conn =
          put(
            conn,
            Routes.product_user_path(conn, :update, org.name, product.name, user.username),
            role: "write"
          )

        assert json_response(conn, 403)["status"] != ""
      end
    end
  end

  defp create_product_user(%{user2: user, product: product}) do
    {:ok, product_user} = Products.add_product_user(product, user, %{role: :admin})
    {:ok, %{product_user: product_user}}
  end
end
