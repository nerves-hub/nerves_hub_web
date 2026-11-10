defmodule NervesHubWeb.Live.Org.ProductsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  test "user is redirected to login when trying to access an org, but the user isn't logged in" do
    build_conn()
    |> visit("/org/snoot")
    |> assert_path("/login")
    |> assert_has("div", text: "You must login to access this page.")
  end

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

    test "view-only members are pointed at the documentation instead of the shared secret", %{
      conn: conn,
      org: org,
      user: user
    } do
      product = Fixtures.product_fixture(user, org, %{name: "Boop"})
      {:ok, shared_secret} = NervesHub.Products.create_shared_secret_auth(product)

      org_user = NervesHub.Accounts.get_org_user!(org, user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      # The device list loads asynchronously, so wait for the empty state
      # before checking what it rendered.
      |> assert_has("h2", text: "#{product.name} doesn't have any devices yet.", timeout: 1000)
      |> unwrap(fn view ->
        html = render(view)
        refute html =~ shared_secret.secret
        html
      end)
      |> assert_has("p", text: "Check the nerves_hub_link documentation for how to connect your first device.")
    end
  end

  describe "products tab" do
    test "heads every organization page with the organization's name, counts and tabs", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}")
      |> assert_has("h1", text: org.name)
      |> assert_has("#org-summary", text: "1 product · 1 device · 1 member")
      |> assert_has("nav a[aria-current='page']", text: "Products")
      |> assert_has("nav a[href='/org/#{org.name}/settings/users']", text: "Users 1")
      |> assert_has("nav a[href='/org/#{org.name}/settings/keys']", text: "Signing keys 1")
      |> assert_has("nav a[href='/org/#{org.name}/settings/certificates']", text: "Certificates 0")
    end

    test "gives a single product a card of its own", %{conn: conn, org: org, product: product, firmware: firmware} do
      _ = Fixtures.device_fixture(org, product, firmware)
      device = Fixtures.device_fixture(org, product, firmware)
      {:ok, device_connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      Connections.device_connected(device_connection.id)

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#product-#{product.id} h2", text: product.name)
      |> assert_has("#product-#{product.id}", text: "fwup firmware")
      # Online counts load after the page renders, as a dash until they arrive.
      |> assert_has("#product-#{product.id} .online-count", text: "1", timeout: 2000)
      |> assert_has("#product-#{product.id}", text: "of 3")
      |> assert_has("#product-#{product.id} nav a[href='/org/#{org.name}/#{product.name}/firmware']", text: "Firmware")
      |> assert_has("#new-product-nudge a[href='/org/#{org.name}/new']", text: "New product")
    end

    test "says so in the card when a product has no devices", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "Quiet"})
      product = Fixtures.product_fixture(user, org, %{name: "Lonely"})

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#product-#{product.id}", text: "No devices yet")
      |> assert_has("#product-#{product.id} a[href='/org/#{org.name}/#{product.name}/devices/new']",
        text: "Connect your first device"
      )
      |> refute_has("#all-clear")
    end

    test "gives two to five products a card each", %{conn: conn, user: user, org: org, product: product} do
      other = Fixtures.product_fixture(user, org, %{name: "Skip"})

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("article#product-#{product.id} h3", text: product.name)
      |> assert_has("article#product-#{other.id} h3", text: other.name)
      |> assert_has("#new-product-tile", text: "New product")
      |> refute_has("#products-filter")
    end

    test "lists more than five products in a table that can be filtered and sorted", %{conn: conn, user: user, org: org} do
      for name <- ~w(Alpha Bravo Charlie Delta Echo) do
        Fixtures.product_fixture(user, org, %{name: name})
      end

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("[role='table'] a[role='row']", count: 6)
      # The product with devices comes first until another order is picked.
      |> assert_has("[role='table'] a[role='row']:first-of-type", text: "Hop")
      |> select("Sort products", option: "Name")
      |> assert_has("[role='table'] a[role='row']:first-of-type", text: "Alpha")
      |> fill_in("Filter products", with: "char")
      |> assert_has("[role='table'] a[role='row']", count: 1)
      |> assert_has("[role='table'] a[role='row']", text: "Charlie")
      |> fill_in("Filter products", with: "zulu")
      |> assert_has("[role='table']", text: "No products match")
    end

    test "says when nothing needs attention", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#all-clear", text: "Nothing needs attention", timeout: 2000)
      |> refute_has("#needs-attention")
    end

    test "puts what needs attention above the products", %{conn: conn, org: org, product: product, device: device} do
      {:ok, _} = Health.save_device_health(%{device_id: device.id, status: :unhealthy})

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#needs-attention .attention-item", text: "1 device is unhealthy", timeout: 2000)
      |> assert_has("#needs-attention .attention-item", text: product.name)
      |> refute_has("#all-clear")
    end

    test "offers a form to create the first product when the organization has none", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "Empty"})

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#org-summary", text: "No products yet · 1 member")
      |> assert_has("h2", text: "Create your first product")
      |> fill_in("Product name", with: "weather-station")
      |> assert_has("#first-product-url", text: "/org/Empty/")
      |> assert_has("#first-product-url .text-content-strong", text: "weather-station")
      |> click_button("Create product")
      |> assert_path("/org/Empty/weather-station/devices")

      {:ok, product} = Products.get_product_by_org_id_and_name(org.id, "weather-station")

      assert product.extensions |> Map.from_struct() |> Map.delete(:id) |> Map.values() |> Enum.all?()
    end

    test "shows why the first product couldn't be created", %{conn: conn, user: user} do
      org = Fixtures.org_fixture(user, %{name: "Empty"})

      conn
      |> visit("/org/#{org.name}")
      |> fill_in("Product name", with: "   ")
      |> click_button("Create product")
      |> assert_path("/org/Empty")
      |> assert_has(".error-text", text: "can't be blank")
    end

    test "tells a member who can't create products that there are none yet", %{conn: conn, user: user} do
      owner = Fixtures.user_fixture()
      org = Fixtures.org_fixture(owner, %{name: "Elsewhere"})
      {:ok, _} = Accounts.add_org_user(org, user, %{role: :view})

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("#no-products h2", text: "Elsewhere doesn’t have any products yet")
      |> refute_has("#first-product-form")
    end
  end

  describe "create product" do
    test "shows an error if the product name is blank", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h2", text: "New Product")
      |> fill_in("Name", with: "    ")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/new")
      |> assert_has(".error-text", text: "can't be blank")
    end

    test "product name required", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h2", text: "New Product")
      |> fill_in("Name", with: "MyAmazingProduct")
      |> click_button("Create Product")
      |> assert_path("/org/#{org.name}/MyAmazingProduct/devices")
      |> assert_has("h2", text: "MyAmazingProduct doesn't have any devices yet", timeout: 1000)
    end

    test "the product always goes to the current org, whatever the form sends", %{conn: conn, org: org} do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)

      conn
      |> visit("/org/#{org.name}/new")
      |> unwrap(fn view ->
        render_submit(view, "create_product", %{
          "product" => %{"name" => "Planted", "org_id" => to_string(other_org.id)}
        })
      end)
      |> assert_path("/org/#{org.name}/Planted/devices")

      assert Repo.get_by!(Product, name: "Planted").org_id == org.id
    end

    test "product name accepts spaces", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/new")
      |> assert_has("h2", text: "New Product")
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
      |> assert_has("h2", text: "New Product")
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
      |> assert_has("h2", text: "New Product")
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
