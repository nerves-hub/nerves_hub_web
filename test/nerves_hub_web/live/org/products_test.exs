defmodule NervesHubWeb.Live.Org.ProductsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  describe "onboarding" do
    test "shows a friendly onboarding page if no devices are registered" do
      user_name = "Waffles"
      user = Fixtures.user_fixture(%{name: user_name})
      org = Fixtures.org_fixture(user, %{name: user_name})
      product = Fixtures.product_fixture(user, org, %{name: "Boop"})

      token = NervesHub.Accounts.create_user_session_token(user)

      build_conn()
      |> init_test_session(%{
        "user_token" => token
      })
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h2", text: "#{product.name} doesn't have any devices yet.", timeout: 1000)
      |> assert_has("p",
        text: "Check the nerves_hub_link documentation for how to connect your first device.",
        timeout: 1000
      )
    end

    test "shows a friendly onboarding page and how to use shared secrets if no devices are registered and a shared secret exists" do
      user_name = "Waffles"
      user = Fixtures.user_fixture(%{name: user_name})
      org = Fixtures.org_fixture(user, %{name: user_name})
      product = Fixtures.product_fixture(user, org, %{name: "Boop"})

      {:ok, shared_secret} = NervesHub.Products.create_shared_secret_auth(product)

      token = NervesHub.Accounts.create_user_session_token(user)

      Application.put_env(:nerves_hub, :devices_websocket_url, "pat.all.the.dogs")

      build_conn()
      |> init_test_session(%{
        "user_token" => token
      })
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h2", text: "#{product.name} doesn't have any devices yet.", timeout: 1000)
      |> assert_has("h3", text: "1. Add the dependency to your mix.exs", timeout: 1000)
      |> assert_has("code", text: "host: \"pat.all.the.dogs\"", timeout: 1000)
      |> assert_has("code", text: "product_key: \"#{shared_secret.key}\"", timeout: 1000)
      |> assert_has("code", text: "product_secret: \"#{shared_secret.secret}\"", timeout: 1000)
    end
  end

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
      |> assert_has("h2", text: "MyAmazingProduct doesn't have any devices yet", timeout: 1000)
    end

    test "product name accepts spaces", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h1", text: "New Product")
      |> fill_in("Name", with: "My Amazing Product")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/My%20Amazing%20Product/devices")
      |> assert_has("h2",
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
      |> assert_has("h2",
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
      |> assert_has("h2",
        text: "My Amazing Product doesn't have any devices yet",
        timeout: 1000
      )
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
end
