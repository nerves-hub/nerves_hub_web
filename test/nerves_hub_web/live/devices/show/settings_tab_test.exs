defmodule NervesHubWeb.Live.Devices.Show.SettingsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Components.DevicePage.SettingsTab
  alias NervesHubWeb.Components.Utils
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadEntry
  alias Phoenix.Socket.Broadcast

  describe "device settings" do
    test "can change tags", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("div", text: "General settings")
      |> fill_in("Tags", with: "josh, lars")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "Device updated")
      |> click_link("Details")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "josh")
      |> assert_has("span", text: "lars")
    end

    test "saves only the form's fields", %{conn: conn, org: org, product: product, device: device} do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> unwrap(fn view ->
        render_submit(view, "update-device-settings", %{
          "device" => %{
            "description" => "still mine",
            "org_id" => to_string(other_org.id),
            "product_id" => to_string(other_product.id)
          }
        })
      end)
      |> assert_has("div", text: "Device updated")

      device = Repo.reload(device)
      assert device.description == "still mine"
      assert device.org_id == org.id
      assert device.product_id == product.id
    end

    test "can add 'first connect code'", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("div", text: "General settings")
      |> fill_in("First connect code", with: "dbg(\"boo\")")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "Device updated")

      device = Devices.get_device(device.id)

      assert device.connecting_code == "dbg(\"boo\")"
    end
  end

  describe "device certificates" do
    test "can upload certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      conn =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        # Device has 1 certificate as default
        |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
        |> upload("Upload certificate", "test/fixtures/ssl/device-test-cert.pem")
        |> assert_has("div", text: "Certificate Upload Successful")
        |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")

      device = Repo.preload(device, :device_certificates, force: true)

      assert Enum.count(device.device_certificates) == 2

      Enum.each(device.device_certificates, fn cert ->
        assert_has(conn, "div", text: "Serial: #{Utils.format_serial(cert.serial)}")
      end)
    end

    test "can delete certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      # Device has 1 certificate as default
      |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
      |> click_button("button[phx-click=\"delete-certificate\"]", "")
      |> refute_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")

      device = Repo.preload(device, :device_certificates, force: true)

      assert Enum.empty?(device.device_certificates)
    end

    test "shows the signer CA when it is registered with the org", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      ca = Fixtures.ca_certificate_fixture(org)
      {:ok, ca_cert} = CACertificates.update_ca_certificate(ca.db_cert, %{description: "Factory signer"})
      Fixtures.device_certificate_fixture_for_ca(device, ca)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("div", text: "Signer CA:")
      |> assert_has("a[href='/org/#{org.name}/settings/certificates/#{ca_cert.serial}']", text: "Factory signer")
    end

    test "shows the signer CA as unknown when it was never registered", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # The fixture device's certificate is signed by a CA which isn't in the DB.
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("div", text: "Signer CA: Unknown")
    end

    test "can download certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      result =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        # Device has 1 certificate as default
        |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
        |> click_link("a[download=\"\"]", "")

      assert result.conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end

  describe "device shared secrets" do
    test "lists the device's keys, when each was last used, and never the secret", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, used} = Devices.create_shared_secret_auth(device)
      :ok = Devices.mark_last_used(used)
      {:ok, unused} = Devices.create_shared_secret_auth(device)
      {:ok, deactivated} = Devices.create_shared_secret_auth(device)
      {:ok, _} = Devices.deactivate_shared_secret_auth(device, deactivated.key, user)

      session =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        |> assert_has("#shared-secrets code", text: used.key)
        |> assert_has("#shared-secrets code", text: unused.key)
        |> assert_has("#shared-secrets code", text: deactivated.key)
        |> assert_has("#shared-secrets span", text: "Never used")
        |> assert_has("#shared-secrets span", text: "Last used")
        |> assert_has("#shared-secrets .tooltip-content", text: "Deactivated by #{user.name}")

      for auth <- [used, unused, deactivated] do
        refute session.conn.resp_body =~ auth.secret
        refute_has(session, "#shared-secrets input[value='#{auth.secret}']")
      end
    end

    test "creating one shows its secret once", %{conn: conn, org: org, product: product, device: device, user: user} do
      session =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        |> assert_has("#shared-secrets div", text: "No shared secrets have been created.")
        |> click_button("Create shared secret")

      assert [%{key: key}] = Devices.list_shared_secret_auths(device)
      assert {:ok, auth} = Devices.get_shared_secret_auth(key)

      session
      |> assert_has("#shared-secrets p", text: "Copy the secret now.")
      |> assert_has("#shared-secrets code", text: auth.key)
      |> assert_has("#shared-secret-new[value='#{auth.secret}']")
      |> click_button("Done")
      |> refute_has("#shared-secret-new")
      |> assert_has("#shared-secrets code", text: auth.key)
      |> assert_has("#shared-secrets .tooltip-content", text: "Created by #{user.name}")

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("#shared-secrets code", text: auth.key)
      |> refute_has("#shared-secret-new")
    end

    test "deactivating one closes connections made with it", %{conn: conn, org: org, product: product, device: device} do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, NervesHub.DeviceEvents.shared_secret_topic(auth.key))

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> click_button("Deactivate")
      |> assert_has("div", text: "The shared secret has been deactivated, and connections made with it closed.")
      |> assert_has("#shared-secrets .tooltip-content", text: "Deactivated by")
      |> assert_has("#shared-secrets span", text: "Deactivated", exact: true)
      |> refute_has("#shared-secrets button", text: "Deactivate")

      assert {:error, :not_found} = Devices.get_shared_secret_auth(auth.key)
      assert_receive %Broadcast{event: "disconnect"}
    end

    test "shows who created and deactivated a key, even after they are deleted", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      other = Fixtures.user_fixture(%{name: "Former Teammate"})
      {:ok, auth} = Devices.issue_shared_secret_auth(device, other)
      {:ok, _} = Devices.deactivate_shared_secret_auth(device, auth.key, user)
      {1, _} = Repo.update_all(from(u in User, where: u.id == ^other.id), set: [deleted_at: DateTime.utc_now(:second)])

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("#shared-secrets .tooltip-content", text: "Created by Former Teammate")
      |> assert_has("#shared-secrets .tooltip-content", text: "Deactivated by #{user.name}")
    end

    test "view-only members can see the keys, but not create or deactivate them", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      org_user = NervesHub.Accounts.get_org_user!(org, user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("#shared-secrets code", text: auth.key)
      |> refute_has("#shared-secrets button", text: "Create shared secret")
      |> refute_has("#shared-secrets button", text: "Deactivate")
    end

    test "are read-only on a deleted device", %{conn: conn, org: org, product: product, device: device} do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      {:ok, device} = Devices.delete_device(device)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> assert_has("#shared-secrets code", text: auth.key)
      |> refute_has("#shared-secrets button", text: "Create shared secret")
      |> refute_has("#shared-secrets button", text: "Deactivate")
    end
  end

  describe "device extensions" do
    test "view-only members cannot change them", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      org_user = NervesHub.Accounts.get_org_user!(org, user.id)
      {:ok, _} = NervesHub.Accounts.change_org_user_role(org_user, :view)

      session = visit(conn, ~p"/org/#{org}/#{product}/devices/#{device}/settings")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "update-extension", %{"extension" => "geo", "value" => "off"}))

      assert Repo.reload(device).extensions.geo
    end
  end

  describe "a member with the view role" do
    setup do
      Repo.update_all(OrgUser, set: [role: :view])

      :ok
    end

    test "can't delete a certificate", %{conn: conn, org: org, product: product, device: device} do
      [cert] = Repo.preload(device, :device_certificates).device_certificates

      session =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
        |> refute_has("button[phx-click=\"delete-certificate\"]")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(session.view, "delete-certificate", %{"serial" => cert.serial}))

      assert [%{serial: serial}] = Repo.preload(device, :device_certificates, force: true).device_certificates
      assert serial == cert.serial
    end

    test "can't upload a certificate", %{conn: conn, org: org, product: product, device: device} do
      session =
        conn
        |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
        |> refute_has("#upload-certificate")

      # No upload is configured for a viewer, so LiveView refuses one before
      # any of the file is sent.
      assert_raise RuntimeError, "no uploads allowed for certificate", fn ->
        file_input(session.view, "#settings-tab", :certificate, [
          %{name: "device-test-cert.pem", content: File.read!("test/fixtures/ssl/device-test-cert.pem")}
        ])
      end

      assert [_default] = Repo.preload(device, :device_certificates, force: true).device_certificates
    end
  end

  # A viewer never gets an upload configured (above), and the scope is fixed
  # when the page mounts, so no page can reach this. It guards the certificate
  # being saved if the upload were ever offered to someone it shouldn't be.
  test "a finished certificate upload is authorized before it is saved" do
    socket = %Socket{assigns: %{__changed__: %{}, current_scope: %Scope{role: :view}}}
    entry = %UploadEntry{upload_config: :certificate, done?: true}

    assert_raise NervesHubWeb.UnauthorizedError, fn ->
      SettingsTab.handle_progress(:certificate, entry, socket)
    end
  end

  test "deleting device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
    |> click_button("Delete device")
    |> assert_has("div", text: "Device is deleted and must be restored to use.")

    assert Repo.reload(device) |> Map.get(:deleted_at)
  end

  test "destroying device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
    |> click_button("Delete device")
    |> click_button("Permanently delete device")
    |> assert_has("div", text: "Device permanently destroyed successfully.")

    refute Repo.reload(device)
  end
end
