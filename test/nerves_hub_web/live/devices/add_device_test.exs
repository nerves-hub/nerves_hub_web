defmodule NervesHubWeb.Live.Devices.AddDeviceTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Devices.Certificates
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  defp new_device_path(org, product), do: "/org/#{org.name}/#{product.name}/devices/new"

  describe "opening the dialog" do
    test "from the devices list, keeping its query", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices?state=online")
      |> click_link("#add-device-button", "Add device")
      |> assert_path(new_device_path(org, product), query_params: %{"state" => "online"})
      |> assert_has("#add-device h2", text: "Add a device")
      |> click_link("#add-device-form a", "Cancel")
      |> assert_path("/org/#{org.name}/#{product.name}/devices", query_params: %{"state" => "online"})
      |> refute_has("#add-device")
    end

    test "is only for members who can add devices", %{org: org, product: product} do
      member = Fixtures.user_fixture()
      {:ok, _} = Accounts.add_org_user(org, member, %{role: :view})

      member
      |> signed_in_conn()
      |> visit(new_device_path(org, product))
      |> refute_has("#add-device")
      |> refute_has("#add-device-button")
    end
  end

  describe "adding a device" do
    # Without one, the dialog starts on a shared secret of the device's own.
    setup %{product: product} do
      {:ok, _auth} = Products.create_shared_secret_auth(product)
      :ok
    end

    test "requires an identifier", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> click_button("Add device")
      |> assert_path(new_device_path(org, product))
      |> assert_has("#add-device-form p", text: "can't be blank")
    end

    test "with the product's shared secret is matched when it connects", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> assert_has("#add-device-connection-product[checked]")
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> fill_in("Description", with: "Probe 14, Lindholmen greenhouse", exact: false)
      |> click_button("Add device")
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("[role=alert]", text: "Added aaabbbccc111222333.")
      |> assert_has("a", text: "aaabbbccc111222333", timeout: 1000)

      device = Devices.get_by_identifier!("aaabbbccc111222333")
      assert device.description == "Probe 14, Lindholmen greenhouse"
      assert Devices.list_shared_secret_auths(device) == []
    end

    test "with tags, including one typed but not yet added", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> unwrap(fn view ->
        view |> element("#add-device-tags-autocomplete") |> render_hook("add-tag", %{"tag" => "josh"})
      end)
      |> assert_has("#add-device-form [data-tag]", text: "josh")
      |> fill_in("Tags", with: "lars", exact: false)
      |> click_button("Add device")
      |> assert_has("[role=alert]", text: "Added aaabbbccc111222333.")

      assert Devices.get_by_identifier!("aaabbbccc111222333").tags == ["josh", "lars"]
    end

    test "names the deployment groups its tags match", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      firmware: firmware
    } do
      Fixtures.deployment_group_fixture(firmware, %{
        name: "Production Fleet",
        conditions: %{"tags" => ["prod"], "version" => ""},
        is_active: true,
        user: user
      })

      conn
      |> visit(new_device_path(org, product))
      |> refute_has("#add-device-matching-groups")
      |> unwrap(fn view ->
        view |> element("#add-device-tags-autocomplete") |> render_hook("add-tag", %{"tag" => "prod"})
      end)
      |> assert_has("#add-device-matching-groups", text: "These tags match Production Fleet")
    end

    test "with a first connect code", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> fill_in("First connect code", with: "IO.puts(\"hello\")")
      |> click_button("Add device")
      |> assert_has("[role=alert]", text: "Added aaabbbccc111222333.")

      assert Devices.get_by_identifier!("aaabbbccc111222333").connecting_code == "IO.puts(\"hello\")"
    end

    test "says when the identifier is taken", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: device.identifier)
      |> click_button("Add device")
      |> assert_path(new_device_path(org, product))
      |> assert_has("#add-device-form p", text: "has already been taken")
    end

    test "ignores a deployment group sent with the form", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      # Not a field on the form, but a client can send it with the event.
      conn
      |> visit(new_device_path(org, product))
      |> unwrap(fn view ->
        view
        |> form("#add-device-form", %{"device" => %{"identifier" => "aaabbbccc111222333"}})
        |> render_submit(%{"device" => %{"deployment_id" => deployment_group.id}})
      end)

      assert is_nil(Devices.get_by_identifier!("aaabbbccc111222333").deployment_id)
    end
  end

  describe "adding a device with a shared secret of its own" do
    test "shows its key and secret once, then waits for it to connect", %{conn: conn, org: org, product: product} do
      session =
        conn
        |> visit(new_device_path(org, product))
        |> fill_in("Identifier", with: "aaabbbccc111222333")
        |> choose("A shared secret of its own", exact: false)
        |> click_button("Add device")
        |> assert_path(new_device_path(org, product))
        |> assert_has("#add-device h2", text: "aaabbbccc111222333 added")

      device = Devices.get_by_identifier!("aaabbbccc111222333")
      auth = Repo.get_by!(SharedSecretAuth, device_id: device.id)

      session
      |> assert_has("#add-device-key", text: auth.key)
      |> assert_has("#add-device-copy-secret[data-copy-value='#{auth.secret}']")
      |> assert_has("#add-device-waiting", text: "Waiting for it to connect")
      |> assert_has("#device-list a", text: "aaabbbccc111222333", timeout: 1000)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{status: "online"}
        })

        render(view)
      end)
      |> assert_has("#add-device-waiting", text: "Connected")
      |> click_link("#add-device-done", "Done")
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> refute_has("#add-device")
    end

    test "can add another after", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> choose("A shared secret of its own", exact: false)
      |> click_button("Add device")
      |> click_button("Add another")
      |> assert_has("#add-device h2", text: "Add a device")
      |> refute_has("#add-device-form input[name='device[identifier]'][value='aaabbbccc111222333']")
    end
  end

  describe "adding a device with its certificate" do
    setup %{tmp_dir: tmp_dir} do
      key = X509.PrivateKey.new_ec(:secp256r1)
      otp_cert = X509.Certificate.self_signed(key, "/CN=aaabbbccc111222333")
      path = Path.join(tmp_dir, "device.pem")
      File.write!(path, X509.Certificate.to_pem(otp_cert))

      %{otp_cert: otp_cert, cert_path: path}
    end

    test "saves the certificate with it", %{conn: conn, org: org, product: product, otp_cert: otp_cert, cert_path: path} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> choose("Its certificate", exact: false)
      |> upload("Choose a certificate", path)
      |> assert_has("[data-certificate-file]", text: "device.pem")
      |> click_button("Add device")
      |> assert_has("[role=alert]", text: "Added aaabbbccc111222333.")

      assert {:ok, device} = Certificates.get_device_by_x509(otp_cert)
      assert device.identifier == "aaabbbccc111222333"
    end

    test "needs no upload for one a CA signed", %{conn: conn, org: org, product: product} do
      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> choose("Its certificate", exact: false)
      |> click_button("Add device")
      |> assert_has("[role=alert]", text: "Added aaabbbccc111222333.")
    end

    test "refuses a file that isn't a certificate", %{conn: conn, org: org, product: product, tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "notes.pem")
      File.write!(path, "not a certificate")

      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> choose("Its certificate", exact: false)
      |> upload("Choose a certificate", path)
      |> click_button("Add device")
      |> assert_has("#add-device-form", text: "This file isn't a certificate in PEM or DER form.")

      assert {:error, :not_found} = Devices.get_device_by(identifier: "aaabbbccc111222333")
    end

    test "refuses a certificate another device has", %{
      conn: conn,
      org: org,
      product: product,
      user: user,
      otp_cert: otp_cert,
      cert_path: path
    } do
      {:ok, _} = Devices.create_device_with_certificate(product, %{identifier: "first-device"}, user, otp_cert)

      conn
      |> visit(new_device_path(org, product))
      |> fill_in("Identifier", with: "aaabbbccc111222333")
      |> choose("Its certificate", exact: false)
      |> upload("Choose a certificate", path)
      |> click_button("Add device")
      |> assert_has("#add-device-form", text: "Another device already has this certificate's key.")

      assert {:error, :not_found} = Devices.get_device_by(identifier: "aaabbbccc111222333")
    end
  end
end
