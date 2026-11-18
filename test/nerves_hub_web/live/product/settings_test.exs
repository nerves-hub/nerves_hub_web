defmodule NervesHubWeb.Live.Product.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: false
  use Mimic

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo

  describe "the page" do
    test "is titled for the product, with its two tabs", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("h1", text: "Product settings")
      |> assert_has("nav a[aria-current='page']", text: "General")
      |> assert_has("nav a", text: "Device health")
      |> refute_has("#read-only-notice")
    end

    test "view-only members are told they can't change anything", %{conn: conn, org: org, user: user, product: product} do
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#read-only-notice", text: "your role in #{org.name} can't change them")
      |> assert_has("#require-unique-firmware-version[disabled]")
      |> refute_has("#delete-product")
    end
  end

  describe "delete product" do
    test "asks for the product's name, then soft deletes it", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_button("Delete product")
      |> assert_has("#confirm-dialog h2", text: "Delete #{product.name}?")
      |> assert_has("#confirm-dialog button[disabled]", text: "Delete #{product.name}")
      |> unwrap(fn view ->
        view |> form("#delete-product-form", %{name: product.name}) |> render_submit()
      end)
      |> assert_path("/org/#{org.name}")
      |> assert_has("div", text: "Deleted #{product.name}.")

      refute is_nil(Repo.reload(product).deleted_at)
    end

    test "a name that doesn't match deletes nothing", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_button("Delete product")
      |> unwrap(fn view ->
        view |> form("#delete-product-form", %{name: "not-#{product.name}"}) |> render_submit()
      end)
      |> assert_has("#confirm-dialog")

      assert is_nil(Repo.reload(product).deleted_at)
    end

    test "is refused while the product has devices", %{conn: conn, org: org, product: product} do
      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#delete-product", text: "1 device is still here")
        |> assert_has("#delete-product-button[disabled]")

      # Counted again when asked, not trusted from the page.
      session
      |> unwrap(&render_click(&1, "delete-product", %{"name" => product.name}))
      |> assert_has("div", text: "#{product.name} still has devices, so it can't be deleted.")

      assert is_nil(Repo.reload(product).deleted_at)
    end

    test "shows an error when deleting fails", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      stub(Products, :delete_product, fn _ ->
        {:error,
         %Ecto.Changeset{errors: [base: {"cannot delete", []}], data: %{}, changes: %{}, types: %{}, valid?: false}}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> click_button("Delete product")
      |> unwrap(fn view ->
        view |> form("#delete-product-form", %{name: product.name}) |> render_submit()
      end)
      |> assert_has("div", text: "#{product.name} couldn't be deleted.")
    end
  end

  describe "unique firmware version setting" do
    test "renders the require unique firmware version toggle", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("span", text: "Require unique firmware versions")
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

      assert html =~ "ESP-IDF application images"
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

      assert html =~ "AtomVM packbeam archives"

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

  describe "require unique firmware version" do
    test "enables the setting", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_change(view, "update-require-unique-firmware-version", %{"value" => "on"})
      end)
      |> assert_has("div", text: "Unique firmware versions are now required.")
    end

    test "disables the setting", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_change(view, "update-require-unique-firmware-version", %{"value" => "off"})
      end)
      |> assert_has("div", text: "Unique firmware versions are now not required.")
    end

    test "shows error when update fails", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      stub(Products, :update_product, fn _, _ ->
        {:error,
         %Ecto.Changeset{errors: [base: {"cannot update", []}], data: %{}, changes: %{}, types: %{}, valid?: false}}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_change(view, "update-require-unique-firmware-version", %{"value" => "on"})
      end)
      |> assert_has("div",
        text: "Failed to update the unique firmware version setting. Please contact support if this problem persists."
      )
    end
  end

  describe "extensions" do
    test "lists extensions by name, with how many devices each is on for", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#extension-row-local_shell", text: "Local shell")
      |> assert_has("#extension-row-network_identity", text: "Network identity")
      |> assert_has("#extension-count-geo", text: "on 1 of 1")
      |> refute_has("[id^=extension-turned-off-]")
    end

    test "turning one on doesn't ask", %{conn: conn, org: org, product: product} do
      {:ok, _} = Products.disable_extension_setting(product, "health")

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#extension-count-health", text: "off")
      |> unwrap(&render_click(&1, "update-extension", %{"extension" => "health", "value" => "on"}))
      |> refute_has("#confirm-dialog")
      |> assert_has("div", text: "Turned Health on for #{product.name}.")
      |> assert_has("#extension-health[checked]")

      assert Repo.reload(product).extensions.health
    end

    test "turning one off asks first", %{conn: conn, org: org, product: product} do
      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> unwrap(&render_click(&1, "update-extension", %{"extension" => "health"}))
        |> assert_has("#confirm-dialog h2", text: "Turn off Health for every device?")
        |> assert_has("#confirm-dialog", text: "1 device has it on now")

      assert Repo.reload(product).extensions.health

      session
      |> within("#confirm-dialog", &click_button(&1, "Turn off Health"))
      |> assert_has("div", text: "Turned Health off for #{product.name}.")
      |> assert_has("#extension-count-health", text: "off")

      refute Repo.reload(product).extensions.health
    end

    # The switch flips in the browser before the dialog asks, so the page has
    # to draw it on again when the answer is no.
    test "the switch is off while it asks, and on again after Cancel", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(&render_click(&1, "update-extension", %{"extension" => "geo"}))
      |> refute_has("#extension-geo[checked]")
      |> unwrap(&render_click(&1, "cancel-confirm", %{}))
      |> refute_has("#confirm-dialog")
      |> assert_has("#extension-geo[checked]")

      assert Repo.reload(product).extensions.geo
    end

    test "shows an error when the extension can't be changed", %{conn: conn, org: org, product: product} do
      stub(Products, :enable_extension_setting, fn _, _ ->
        {:error,
         %Ecto.Changeset{errors: [base: {"cannot update", []}], data: %{}, changes: %{}, types: %{}, valid?: false}}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(&render_click(&1, "update-extension", %{"extension" => "health", "value" => "on"}))
      |> assert_has("div",
        text: "Failed to update the Health extension. Please contact support if this problem persists."
      )
    end

    test "devices that turned one off on their own can have it turned back on", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      device: device
    } do
      second = Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Devices.disable_extension_setting(device, "geo")

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#extension-count-geo", text: "on 1 of 2")
      |> assert_has("#extension-turned-off-geo", text: "1 device has Geo turned off in its own setting.")
      |> click_button("Turn it back on for it")
      |> assert_has("#confirm-dialog h2", text: "Turn Geo back on for 1 device?")
      |> click_button("Turn on for 1 device")
      |> unwrap(&render_async/1)
      |> assert_has("div", text: "Turned Geo back on for 1 device.")
      |> assert_has("#extension-count-geo", text: "on 2 of 2")
      |> refute_has("#extension-turned-off-geo")

      assert Repo.reload(device).extensions.geo
      assert Repo.reload(second).extensions.geo
    end

    test "turning one back on is refused while it's already running", %{conn: conn, org: org, product: product} do
      test_pid = self()

      stub(BulkActions, :set_extension_for_product, fn _product, extension, _enabled, _user ->
        send(test_pid, {:started, extension, self()})

        receive do
          :finish -> {:ok, 1}
        end
      end)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> unwrap(&render_click(&1, "set-extension-for-devices", %{"extension" => "geo", "enabled" => "true"}))

      assert_receive {:started, "geo", task}

      unwrap(session, &render_click(&1, "set-extension-for-devices", %{"extension" => "geo", "enabled" => "true"}))

      refute_receive {:started, "geo", _task}

      send(task, :finish)
    end

    test "an unknown extension is refused", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_click(view, "set-extension-for-devices", %{"extension" => "teleport", "enabled" => "true"})
        render_async(view)
      end)
      |> assert_has("div", text: "That extension isn't one this platform supports.")
    end

    test "view-only members cannot change extensions, for the product or its devices", %{
      conn: conn,
      org: org,
      user: user,
      product: product,
      device: device
    } do
      {:ok, _} = Devices.disable_extension_setting(device, "geo")
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#extension-geo[disabled]")
        |> assert_has("#extension-turned-off-geo")
        |> refute_has("#reenable-extension-geo")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "update-extension", %{"extension" => "geo", "value" => "off"}))

      for event <- ["prepare-reenable-extension", "set-extension-for-devices"] do
        session = visit(conn, "/org/#{org.name}/#{product.name}/settings")

        assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
                 catch_exit(render_click(session.view, event, %{"extension" => "geo", "enabled" => "true"}))
      end

      assert Repo.reload(product).extensions.geo
      refute Repo.reload(device).extensions.geo
    end
  end

  describe "device-managed updates" do
    test "new devices can be let choose their update mode", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("span", text: "Let new devices choose their update mode")
      |> unwrap(fn view ->
        render_click(view, "update-default-managed-updates-allowed", %{"value" => "on"})
      end)
      |> assert_has("div", text: "New devices may choose their own update mode.")
      |> assert_has("#default-managed-updates-allowed[checked]")

      assert Repo.reload(product).default_managed_updates_allowed
    end

    test "new devices can be stopped choosing their update mode", %{conn: conn, org: org, product: product} do
      {:ok, _} = Products.update_product(product, %{default_managed_updates_allowed: true})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_click(view, "update-default-managed-updates-allowed", %{})
      end)
      |> assert_has("div", text: "New devices may not choose their own update mode.")

      refute Repo.reload(product).default_managed_updates_allowed
    end

    test "every device in the product can be allowed, and revoked, after asking", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      device: device
    } do
      second = Fixtures.device_fixture(org, product, firmware)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#managed-updates-count", text: "0 of 2 can choose their update mode.")
        |> assert_has("#revoke-managed-updates-on-devices[disabled]")
        |> click_button("#allow-managed-updates-on-devices", "Allow on all")
        |> assert_has("#confirm-dialog h2", text: "Let every device choose its update mode?")
        |> assert_has("#confirm-dialog", text: "2 devices can't choose now")

      refute Repo.reload(device).managed_updates_allowed

      session =
        session
        |> within("#confirm-dialog", &click_button(&1, "Allow on all"))
        |> unwrap(&render_async/1)
        |> assert_has("div", text: "Every device in #{product.name} can now choose its update mode.")
        |> assert_has("#managed-updates-count", text: "2 of 2 can choose their update mode.")
        |> refute_has("#managed-updates-progress")

      assert Repo.reload(device).managed_updates_allowed
      assert Repo.reload(second).managed_updates_allowed

      session
      |> click_button("#revoke-managed-updates-on-devices", "Revoke on all")
      |> assert_has("#confirm-dialog", text: "2 devices can choose now")
      |> within("#confirm-dialog", &click_button(&1, "Revoke on all"))
      |> unwrap(&render_async/1)
      |> assert_has("div", text: "No device in #{product.name} can choose its update mode now.")

      refute Repo.reload(device).managed_updates_allowed
      refute Repo.reload(second).managed_updates_allowed
    end

    test "shows how far it has got, with both buttons waiting", %{conn: conn, org: org, product: product} do
      test_pid = self()

      stub(BulkActions, :set_managed_updates_allowed_for_product, fn _product, _enabled, _user, opts ->
        opts[:on_progress].(1, 4)
        send(test_pid, {:started, self()})

        receive do
          :finish -> %{ok: 4, error: 0}
        end
      end)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> unwrap(&render_click(&1, "set-managed-updates-allowed-for-devices", %{"enabled" => "true"}))

      assert_receive {:started, task}

      session
      |> unwrap(&render/1)
      |> assert_has("#managed-updates-progress", text: "Allowing · 1 of 4 done")
      |> assert_has("#allow-managed-updates-on-devices[disabled]")
      |> assert_has("#revoke-managed-updates-on-devices[disabled]")
      |> tap(fn _ -> send(task, :finish) end)
      |> unwrap(&render_async/1)
      |> refute_has("#managed-updates-progress")
    end

    # The buttons are disabled while one runs, but the event can still be sent.
    test "a second run is refused while one is going", %{conn: conn, org: org, product: product} do
      test_pid = self()

      stub(BulkActions, :set_managed_updates_allowed_for_product, fn _product, enabled, _user, _opts ->
        send(test_pid, {:started, enabled, self()})

        receive do
          :finish -> %{ok: 1, error: 0}
        end
      end)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> unwrap(&render_click(&1, "set-managed-updates-allowed-for-devices", %{"enabled" => "true"}))

      assert_receive {:started, true, task}

      session
      |> unwrap(&render_click(&1, "set-managed-updates-allowed-for-devices", %{"enabled" => "false"}))
      |> assert_has("#managed-updates-progress", text: "Allowing")

      refute_receive {:started, false, _task}

      send(task, :finish)
    end

    test "says how many devices couldn't be changed", %{conn: conn, org: org, product: product} do
      stub(BulkActions, :set_managed_updates_allowed_for_product, fn _product, _enabled, _user, _opts ->
        %{ok: 3, error: 2}
      end)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> unwrap(fn view ->
        render_click(view, "set-managed-updates-allowed-for-devices", %{"enabled" => "true"})
        render_async(view)
      end)
      |> assert_has("div", text: "3 devices can now choose their update mode.")
      |> refute_has("div", text: "Every device in #{product.name}")
      |> assert_has("div", text: "2 devices couldn't be changed. Allow on all again to try them.")
    end

    test "view-only members cannot change the default or the devices", %{
      conn: conn,
      org: org,
      user: user,
      product: product,
      device: device
    } do
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#default-managed-updates-allowed[disabled]")
        |> refute_has("#allow-managed-updates-on-devices")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "update-default-managed-updates-allowed", %{"value" => "on"}))

      for event <- ["prepare-managed-updates", "set-managed-updates-allowed-for-devices"] do
        session = visit(conn, "/org/#{org.name}/#{product.name}/settings")

        assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
                 catch_exit(render_click(session.view, event, %{"enabled" => "true"}))
      end

      refute Repo.reload(product).default_managed_updates_allowed
      refute Repo.reload(device).managed_updates_allowed
    end
  end

  describe "shared secrets" do
    setup do
      original = Application.get_env(:nerves_hub, NervesHubWeb.DeviceSocket)
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])
      on_exit(fn -> Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, original) end)
    end

    test "shared secrets not enabled", %{conn: conn, org: org, user: user} do
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])

      product = Fixtures.product_fixture(user, org, %{})

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("p", text: "Shared secret authentication hasn't been turned on for this platform.")
      |> refute_has("#create-shared-secret")
    end

    test "creating one doesn't ask, and marks it new", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#shared-secrets p", text: "There are no shared secrets yet.")
        |> click_button("Create secret")
        |> refute_has("#confirm-dialog")

      [auth] = Products.load_shared_secret_auth(product).shared_secret_auths

      session
      |> assert_has("#shared-secret-row-#{auth.id} code", text: auth.key)
      |> assert_has("#shared-secret-row-#{auth.id}", text: "New")
    end

    test "deactivating one asks first", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, auth} = Products.create_shared_secret_auth(product)

      session =
        conn
        |> visit("/org/#{org.name}/#{product.name}/settings")
        |> assert_has("#shared-secret-row-#{auth.id} code", text: auth.key)
        |> click_button("#shared-secret-row-#{auth.id} button", "Deactivate")
        |> assert_has("#confirm-dialog h2", text: "Deactivate this shared secret?")

      assert is_nil(Repo.reload(auth).deactivated_at)

      session
      |> within("#confirm-dialog", &click_button(&1, "Deactivate secret"))
      |> assert_has("div", text: "Deactivated #{auth.key}.")
      |> assert_has("#shared-secret-row-#{auth.id}", text: "Deactivated")
      |> refute_has("#shared-secret-#{auth.id}")

      refute is_nil(Repo.reload(auth).deactivated_at)
    end

    # A shared secret lets a device connect and register itself, which a
    # view-only member cannot otherwise do.
    test "view-only members see the key but not the secret", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, auth} = Products.create_shared_secret_auth(product)

      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#shared-secret-row-#{auth.id} code", text: auth.key)
      |> unwrap(fn view ->
        html = render(view)
        refute html =~ auth.secret
        html
      end)
      |> refute_has("#shared-secret-#{auth.id}")
      |> refute_has("#create-shared-secret")
      |> refute_has("#shared-secret-row-#{auth.id} button", text: "Deactivate")
    end

    test "manage members can copy the secret", %{conn: conn, org: org, user: user} do
      product = Fixtures.product_fixture(user, org)
      {:ok, auth} = Products.create_shared_secret_auth(product)

      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :manage)

      conn
      |> visit("/org/#{org.name}/#{product.name}/settings")
      |> assert_has("#shared-secret-#{auth.id}[phx-hook='CopyToClipboard']")
      |> unwrap(fn view ->
        assert view |> element("#shared-secret-#{auth.id}") |> render() =~ ~s(data-copy-value="#{auth.secret}")
        render(view)
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

    refute html =~ "ESP-IDF application images"
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

    refute html =~ "AtomVM packbeam archives"
  end

  test "a format with no unsigned variant does not crash the unsigned toggle", %{
    conn: conn,
    org: org,
    user: user
  } do
    Application.put_env(:nerves_hub, :rauc_firmware_enabled, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :rauc_firmware_enabled, false) end)

    product = Fixtures.product_fixture(user, org)
    {:ok, view, html} = live(conn, "/org/#{org.name}/#{product.name}/settings")

    assert html =~ "RAUC bundles"
    # RAUC will not build an unsigned bundle, so no toggle is rendered for it.
    refute html =~ "Allow unsigned RAUC"

    # The event is still reachable by anything that can send one, and matching
    # only the formats that *do* carry an unsigned field made that a
    # CaseClauseError rather than a no-op.
    assert render_click(view, "update-allow-unsigned", %{"tool" => "rauc", "value" => "on"})

    assert NervesHub.Repo.reload(product).allowed_update_tools == ["fwup"]
  end
end
