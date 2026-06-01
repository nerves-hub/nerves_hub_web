defmodule NervesHubWeb.Live.Product.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo

  describe "banner image" do
    test "shows the picker with Blank selected when no banner exists", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("label", text: "Choose banner image")
      |> assert_has("[phx-value-banner=''][aria-pressed]")
    end

    test "uploads a banner image", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      banner_path = create_test_image(tmp_dir, "banner.png")

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> upload("Choose banner image", banner_path)
      |> assert_has("div", text: "Banner image uploaded successfully.")

      product = Repo.reload(product)
      assert product.banner_upload_key =~ "products/#{product.id}/banner.png"
    end

    test "selects a default banner", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_click(view, "select-banner", %{"banner" => "automotive.jpg"})
      end)
      |> assert_has("div", text: "Banner updated.")
      |> assert_has("[phx-value-banner='automotive.jpg'][aria-pressed]")

      product = Repo.reload(product)
      assert product.banner_upload_key == "default/automotive.jpg"
    end

    test "removes a banner by selecting Blank", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      banner_path = create_test_image(tmp_dir, "banner.png")

      {:ok, product} = Products.update_product_banner(product, banner_path)
      assert product.banner_upload_key

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_click(view, "select-banner", %{"banner" => ""})
      end)
      |> assert_has("div", text: "Banner removed.")
      |> assert_has("[phx-value-banner=''][aria-pressed]")

      product = Repo.reload(product)
      assert is_nil(product.banner_upload_key)
    end

    test "replaces an existing banner image", %{conn: conn, org: org, user: user, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org)
      banner_path = create_test_image(tmp_dir, "banner.png")

      {:ok, product} = Products.update_product_banner(product, banner_path)
      old_key = product.banner_upload_key

      new_banner_path = create_test_image(tmp_dir, "banner2.jpg")

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> upload("Choose banner image", new_banner_path)
      |> assert_has("div", text: "Banner image uploaded successfully.")

      product = Repo.reload(product)
      assert product.banner_upload_key =~ "banner.jpg"
      refute product.banner_upload_key == old_key
    end

    defp create_test_image(dir, filename) do
      path = Path.join(dir, filename)
      # Minimal valid PNG: 1x1 pixel
      png_data =
        <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119,
          83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 2, 0, 1, 226, 33, 188, 51, 0, 0, 0,
          0, 73, 69, 78, 68, 174, 66, 96, 130>>

      File.write!(path, png_data)
      path
    end
  end

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
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
    end

    test "shared secrets not enabled", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])

      product = Fixtures.product_fixture(user, org, %{})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("p", text: "Shared Secret authentication hasn't been enabled for your platform.")
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
end
