defmodule NervesHubWeb.Live.Product.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products

  describe "update product" do
    test "delta firmware updates", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})
      refute product.delta_updatable

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product Settings")
      |> check("Enable delta firmware updates")

      product = NervesHub.Repo.reload(product)
      assert product.delta_updatable
    end
  end

  describe "delete product" do
    test "soft deletes the product", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product Settings")
      |> click_button("Remove Product")
      |> assert_has("div", text: "Product deleted successfully.")
      |> assert_path("/org/#{org.name}")

      product = NervesHub.Repo.reload(product)
      refute is_nil(product.deleted_at)
    end

    test "shows an error if the product has a device", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})

      firmware =
        org
        |> Fixtures.org_key_fixture(user)
        |> Fixtures.firmware_fixture(product)

      Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product Settings")
      |> click_button("Remove Product")
      |> assert_has("div",
        text:
          "There was an error deleting the Product. Please delete all Firmware and Devices first."
      )
      |> assert_path("/org/#{org.name}/#{product.name}/settings")

      product = NervesHub.Repo.reload(product)
      assert is_nil(product.deleted_at)
    end

    test "shows an error if the product has firmware", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})

      org
      |> Fixtures.org_key_fixture(user)
      |> Fixtures.firmware_fixture(product)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product Settings")
      |> click_button("Remove Product")
      |> assert_has("div",
        text:
          "There was an error deleting the Product. Please delete all Firmware and Devices first."
      )
      |> assert_path("/org/#{org.name}/#{product.name}/settings")

      product = NervesHub.Repo.reload(product)
      assert is_nil(product.deleted_at)
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
      |> assert_has("p", text: "This feature hasn't been enabled for this server.")
    end

    test "add shared secret", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> click_button("Add your first Shared Secret.")

      for ss <- Products.load_shared_secret_auth(product).shared_secret_auths do
        assert_has(conn, "td", text: ss.key)
      end
    end

    test "deactivate shared secret", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

      product = Fixtures.product_fixture(user, org, %{delta_updatable: false})

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
          assert_has(conn, ".deactivated", text: Date.to_string(ss.deactivated_at))
        end
      end)
    end
  end
end
