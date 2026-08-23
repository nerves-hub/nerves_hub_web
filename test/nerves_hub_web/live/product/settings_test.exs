defmodule NervesHubWeb.Live.Product.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo

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

  describe "unique firmware version setting" do
    test "renders the require unique firmware version toggle", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("div", text: "Require unique firmware versions")
    end
  end

  describe "esp-idf settings" do
    test "toggling acceptance also reveals the unsigned setting", %{
      conn: conn,
      org: org,
      user: user
    } do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      assert html =~ "Accept ESP-IDF application images"
      # Only meaningful once the format is accepted at all.
      refute html =~ "Allow unsigned ESP-IDF images"

      html =
        view
        |> element("#allow-esp-idf-firmware")
        |> render_click(%{"value" => "on"})

      assert html =~ "Allow unsigned ESP-IDF images"
      assert Repo.reload(product).allowed_update_tools == ["fwup", "esp-idf"]

      html =
        view
        |> element("#allow-unsigned-esp-idf-firmware")
        |> render_click(%{"value" => "on"})

      assert html =~ "Unsigned ESP-IDF application images are now allowed"
      assert Repo.reload(product).allow_unsigned_esp_idf_firmware
    end

    test "turning acceptance back off keeps fwup", %{conn: conn, org: org, user: user} do
      product = Fixtures.esp_idf_product_fixture(user, org)
      {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      view
      |> element("#allow-esp-idf-firmware")
      |> render_click(%{})

      assert Repo.reload(product).allowed_update_tools == ["fwup"]
    end
  end

  describe "atomvm settings" do
    test "toggling acceptance adds the format", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      assert html =~ "Accept AtomVM packbeam archives"

      html =
        view
        |> element("#allow-atomvm-firmware")
        |> render_click(%{"value" => "on"})

      assert html =~ "AtomVM packbeam archives are now accepted"
      assert Repo.reload(product).allowed_update_tools == ["fwup", "atomvm"]
    end

    # Only meaningful once the format is accepted at all, same as ESP-IDF.
    test "the unsigned setting appears once the format is accepted", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      refute html =~ "Allow unsigned AtomVM archives"

      html =
        view
        |> element("#allow-atomvm-firmware")
        |> render_click(%{"value" => "on"})

      assert html =~ "Allow unsigned AtomVM archives"

      html =
        view
        |> element("#allow-unsigned-atomvm-firmware")
        |> render_click(%{"value" => "on"})

      assert html =~ "Unsigned AtomVM packbeam archives are now allowed"
      assert Repo.reload(product).allow_unsigned_atomvm_firmware
    end

    # Turning the format on gives signed-only until someone says otherwise.
    test "unsigned archives are refused by default", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      view |> element("#allow-atomvm-firmware") |> render_click(%{"value" => "on"})

      refute Repo.reload(product).allow_unsigned_atomvm_firmware
    end

    # Two formats, two settings: allowing one unsigned must not allow the other.
    test "the unsigned settings are independent", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      view |> element("#allow-esp-idf-firmware") |> render_click(%{"value" => "on"})
      view |> element("#allow-atomvm-firmware") |> render_click(%{"value" => "on"})
      view |> element("#allow-unsigned-atomvm-firmware") |> render_click(%{"value" => "on"})

      reloaded = Repo.reload(product)
      assert reloaded.allow_unsigned_atomvm_firmware
      refute reloaded.allow_unsigned_esp_idf_firmware
    end

    # Each toggle adds or removes its own format. Rewriting the list, as the
    # ESP-IDF toggle used to, silently dropped whichever others were set.
    test "toggling one format leaves the others alone", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, view, _html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

      view |> element("#allow-esp-idf-firmware") |> render_click(%{"value" => "on"})
      view |> element("#allow-atomvm-firmware") |> render_click(%{"value" => "on"})

      assert Enum.sort(Repo.reload(product).allowed_update_tools) == ["atomvm", "esp-idf", "fwup"]

      view |> element("#allow-esp-idf-firmware") |> render_click(%{})

      assert Enum.sort(Repo.reload(product).allowed_update_tools) == ["atomvm", "fwup"]
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

defmodule NervesHubWeb.Live.Product.SettingsPlatformGateTest do
  # Not async: the platform gate is global application state, and flipping it
  # while another suite is uploading firmware would change that suite's answer.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  test "the esp-idf settings are hidden when the platform has not enabled esp-idf", %{
    conn: conn,
    org: org,
    user: user
  } do
    Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :esp_idf_firmware_enabled, true) end)

    product = Fixtures.product_fixture(user, org)
    {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

    refute html =~ "Accept ESP-IDF application images"
  end

  test "the atomvm settings are hidden when the platform has not enabled atomvm", %{
    conn: conn,
    org: org,
    user: user
  } do
    Application.put_env(:nerves_hub, :atomvm_firmware_enabled, false)
    on_exit(fn -> Application.put_env(:nerves_hub, :atomvm_firmware_enabled, true) end)

    product = Fixtures.product_fixture(user, org)
    {:ok, _view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

    refute html =~ "Accept AtomVM packbeam archives"
  end
end
