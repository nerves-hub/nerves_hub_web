defmodule NervesHubWeb.Live.Org.ProductsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products

  describe "list products" do
    test "suggests you create a product if your org is empty", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user)

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("h2", text: "#{org.name} doesn't have any products yet")
      |> click_link("Create New")
      |> assert_path("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
    end

    test "lists all products in the org", %{conn: conn, org: org, fixture: %{product: product}} do
      conn
      |> visit("/org/#{org.name}")
      |> assert_has("a", text: product.name)
    end
  end

  describe "create product" do
    test "shows an error if the product name is blank", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "    ")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/new")
      |> assert_has(".error-text", text: "can't be blank")
    end

    test "product name required", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "MyAmazingProduct")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/MyAmazingProduct/devices")
      |> assert_has("span", text: "MyAmazingProduct doesn't have any devices yet", timeout: 1000)
    end

    test "product name accepts spaces", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "My Amazing Product")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/My%20Amazing%20Product/devices")
      |> assert_has("span",
        text: "My Amazing Product doesn't have any devices yet",
        timeout: 1000
      )
    end

    test "trims whitespace around the product name, and creates a new product when given a non blank name",
         %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "  My Amazing Product  ")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/My%20Amazing%20Product/devices")
      |> assert_has("span",
        text: "My Amazing Product doesn't have any devices yet",
        timeout: 1000
      )
    end

    test "trims extra whitespace in the product name, and creates a new product when given a non blank name",
         %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "  My  Amazing  Product  ")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/My%20Amazing%20Product/devices")
      |> assert_has("span",
        text: "My Amazing Product doesn't have any devices yet",
        timeout: 1000
      )
    end
  end

  describe "product banner display" do
    test "shows product with banner background", %{conn: conn, org: org, fixture: %{product: product}, tmp_dir: tmp_dir} do
      banner_path = create_test_image(tmp_dir, "banner.png")
      {:ok, _product} = Products.update_product_banner(product, banner_path)

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("a", text: product.name)
      |> assert_has("div[style*='background-image']")
    end

    test "shows product without banner background when no banner", %{conn: conn, org: org, fixture: %{product: product}} do
      conn
      |> visit("/org/#{org.name}")
      |> assert_has("a", text: product.name)
      |> refute_has("div[style*='background-image']")
    end
  end

  describe "authorization and scoping" do
    test "can't view products from other orgs", %{conn: conn} do
      user = Fixtures.user_fixture(%{name: "Josh"})
      org = Fixtures.org_fixture(user, %{name: "JoshCorp"})

      assert_error_sent(404, fn ->
        visit(conn, "/org/#{org.name}")
      end)
    end
  end

  defp create_test_image(dir, filename) do
    path = Path.join(dir, filename)

    png_data =
      <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119,
        83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0,
        73, 69, 78, 68, 174, 66, 96, 130>>

    File.write!(path, png_data)
    path
  end
end
