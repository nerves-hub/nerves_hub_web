defmodule NervesHubWeb.Live.Org.ProductsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products

  describe "list products" do
    test "suggests you create a product if your org is empty", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user)

      conn
      |> visit("/orgs/#{hashid(org)}")
      |> assert_has("h3", text: "#{org.name} doesn’t have any products yet")
      |> click_link("Create New")
      |> assert_path("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
    end

    test "lists all products in the org", %{conn: conn, org: org, fixture: %{product: product}} do
      conn
      |> visit("/orgs/#{hashid(org)}")
      |> assert_has("h3", text: product.name)
    end
  end

  describe "create product" do
    test "shows an error if the product name is blank", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
      |> fill_in("Name", with: "    ")
      |> click_button("Create Product")
      |> assert_path("/orgs/#{hashid(org)}/new")
      |> assert_has("p", text: "Something went wrong! Please check the errors below.")
      |> assert_has(".help-block", text: "can't be blank")
    end

    test "product name required", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
      |> fill_in("Name", with: "MyAmazingProduct")
      |> click_button("Create Product")
      |> tap(fn view ->
        {:ok, product} = Products.get_product_by_org_id_and_name(org.id, "MyAmazingProduct")
        assert_path(view, "/products/#{hashid(product)}/devices")
      end)
      |> assert_has("h3", text: "MyAmazingProduct doesn’t have any devices yet")
    end

    test "product name accepts spaces", %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
      |> fill_in("Name", with: "My Amazing Product")
      |> click_button("Create Product")
      |> tap(fn view ->
        {:ok, product} = Products.get_product_by_org_id_and_name(org.id, "My Amazing Product")
        assert_path(view, "/products/#{hashid(product)}/devices")
      end)
      |> assert_has("h3", text: "My Amazing Product doesn’t have any devices yet")
    end

    test "trims whitespace around the product name, and creates a new product when given a non blank name",
         %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
      |> fill_in("Name", with: "  My Amazing Product  ")
      |> click_button("Create Product")
      |> tap(fn view ->
        {:ok, product} = Products.get_product_by_org_id_and_name(org.id, "My Amazing Product")
        assert_path(view, "/products/#{hashid(product)}/devices")
      end)
      |> assert_has("h3", text: "My Amazing Product doesn’t have any devices yet")
    end

    test "trims extra whitespace in the product name, and creates a new product when given a non blank name",
         %{conn: conn, org: org} do
      conn
      |> visit("/orgs/#{hashid(org)}/new")
      |> assert_has("h1", text: "Create Product")
      |> fill_in("Name", with: "  My  Amazing  Product  ")
      |> click_button("Create Product")
      |> tap(fn view ->
        {:ok, product} = Products.get_product_by_org_id_and_name(org.id, "My Amazing Product")
        assert_path(view, "/products/#{hashid(product)}/devices")
      end)
      |> assert_has("h3", text: "My Amazing Product doesn’t have any devices yet")
    end
  end

  describe "authorization and scoping" do
    test "can't view products from other orgs", %{conn: conn} do
      user = Fixtures.user_fixture(%{name: "Josh"})
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      assert_error_sent(404, fn ->
        visit(conn, "/orgs/#{hashid(org)}")
      end)
    end
  end
end
