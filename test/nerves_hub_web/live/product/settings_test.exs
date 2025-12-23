defmodule NervesHubWeb.Live.Product.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products

  describe "delete product" do
    test "soft deletes the product", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product Settings")
      |> click_button("Delete product")
      |> assert_has("div", text: "Product deleted successfully.")
      |> assert_path("/org/#{org.name}")

      product = NervesHub.Repo.reload(product)
      refute is_nil(product.deleted_at)
    end
  end

  describe "shared secrets" do
    setup do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket,
        shared_secrets: [enabled: false]
      )
    end

    test "shared secrets not enabled", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket,
        shared_secrets: [enabled: false]
      )

      product = Fixtures.product_fixture(user, org, %{})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("p",
        text: "Shared Secret authentication hasn't been enabled for your platform."
      )
    end

    test "add shared secret", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      product = Fixtures.product_fixture(user, org)

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> click_button("Create a Shared Secret")

      for ss <- Products.load_shared_secret_auth(product).shared_secret_auths do
        assert_has(conn, "td", text: ss.key)
      end
    end

    test "deactivate shared secret", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      product = Fixtures.product_fixture(user, org)

      {:ok, _} = Products.create_shared_secret_auth(product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> tap(fn conn ->
        for ss <- Products.load_shared_secret_auth(product).shared_secret_auths do
          assert_has(conn, "td", text: ss.key)
        end
      end)
      |> click_button("Deactivate")
      |> tap(fn conn ->
        for ss <- Products.load_shared_secret_auth(product).shared_secret_auths do
          refute is_nil(ss.deactivated_at)
          assert_has(conn, "span", text: Date.to_string(ss.deactivated_at))
        end
      end)
    end
  end

  describe "product api keys" do
    test "add product api key", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> fill_in("#product-api-key-name", "Key description", with: "My API Key")
        |> click_button("Create Product API Key")

      conn
      |> assert_has("td", text: "My API Key")

      for api_key <- Products.load_product_api_keys(product).product_api_keys do
        assert api_key.name == "My API Key"
      end
    end

    test "add product api key with name", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      {:ok, _api_key} = Products.create_product_api_key(product, %{name: "Test Key"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("td", text: "Test Key")
    end

    test "deactivate product api key", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      {:ok, _} = Products.create_product_api_key(product, %{name: "Test Key"})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_button("Deactivate")
      |> tap(fn conn ->
        for api_key <- Products.load_product_api_keys(product).product_api_keys do
          refute is_nil(api_key.deactivated_at)
          assert_has(conn, "span", text: Date.to_string(api_key.deactivated_at))
        end
      end)
    end

    test "shows empty state when no api keys exist", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("p", text: "You don't have any Product API Keys configured.")
    end
  end
end
