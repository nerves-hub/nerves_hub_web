defmodule NervesHubWeb.Live.Devices.Show.SettingsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Ecto.Query

  alias NervesHub.Accounts.User
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Components.Utils
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

      assert [auth] = Devices.list_shared_secret_auths(device)

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

    test "deactivating one disconnects the device", %{conn: conn, org: org, product: product, device: device} do
      {:ok, auth} = Devices.create_shared_secret_auth(device)
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device_socket:#{device.id}")

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/settings")
      |> click_button("Deactivate")
      |> assert_has("div", text: "The shared secret has been deactivated, and the device disconnected.")
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
