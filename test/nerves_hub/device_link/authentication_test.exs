defmodule NervesHub.DeviceLink.AuthenticationTest do
  # Not async: shared secrets are switched on through application env.
  use NervesHub.DataCase

  alias NervesHub.Accounts
  alias NervesHub.DeviceLink.Authentication
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Repo
  alias NervesHub.Support.Utils
  alias Plug.Crypto.Keys

  setup do
    Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: true])

    on_exit(fn ->
      Application.put_env(:nerves_hub, NervesHubWeb.DeviceSocket, shared_secrets: [enabled: false])
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    {:ok, auth} = Products.create_shared_secret_auth(product)

    %{auth: auth, user: user, org: org}
  end

  describe "authenticate/2 with the hostname the device asked for" do
    setup %{auth: auth, user: user} do
      identifier = Ecto.UUID.generate()
      credentials = {:shared_secret, Map.new(Utils.nh1_key_secret_headers(auth, identifier))}

      %{
        identifier: identifier,
        credentials: credentials,
        other_org: Fixtures.org_fixture(user, %{name: "other_org"})
      }
    end

    test "admits a device on a hostname no org has claimed", %{credentials: credentials} do
      assert {:ok, _} = Authentication.authenticate(credentials, "link.example.com")
    end

    test "admits a device that asked for none", %{credentials: credentials, other_org: other_org} do
      {:ok, _} = Accounts.set_org_device_hostnames(other_org, ["link.example.com"])

      assert {:ok, _} = Authentication.authenticate(credentials, nil)
      assert {:ok, _} = Authentication.authenticate(credentials)
    end

    test "admits a device on a hostname its org has claimed, in any spelling", %{
      credentials: credentials,
      org: org
    } do
      {:ok, _} = Accounts.set_org_device_hostnames(org, ["link.example.com"])

      assert {:ok, _} = Authentication.authenticate(credentials, "link.example.com")
      assert {:ok, _} = Authentication.authenticate(credentials, "LINK.example.com.")
    end

    test "admits a device on a hostname its org shares with another", %{
      credentials: credentials,
      org: org,
      other_org: other_org
    } do
      {:ok, _} = Accounts.set_org_device_hostnames(org, ["link.example.com"])
      {:ok, _} = Accounts.set_org_device_hostnames(other_org, ["link.example.com"])

      assert {:ok, _} = Authentication.authenticate(credentials, "link.example.com")
    end

    test "refuses a device on a hostname only other orgs have claimed, and says why", %{
      credentials: credentials,
      identifier: identifier,
      org: org,
      other_org: other_org
    } do
      {:ok, _} = Accounts.set_org_device_hostnames(other_org, ["link.example.com"])

      ref = :telemetry_test.attach_event_handlers(self(), [[:nerves_hub, :devices, :invalid_auth]])

      assert {:error, :invalid_auth} = Authentication.authenticate(credentials, "LINK.example.com")

      org_id = org.id

      assert_received {[:nerves_hub, :devices, :invalid_auth], ^ref, _,
                       %{reason: :wrong_hostname, server_name: "LINK.example.com", org_id: ^org_id}}

      # It hasn't connected, so it hasn't been provisioned.
      assert %{status: :registered} = Repo.get_by!(Device, identifier: identifier)
    end

    test "a deleted org's claim no longer counts", %{credentials: credentials, other_org: other_org} do
      {:ok, other_org} = Accounts.set_org_device_hostnames(other_org, ["link.example.com"])
      {:ok, _} = Accounts.soft_delete_org(other_org)

      assert {:ok, _} = Authentication.authenticate(credentials, "link.example.com")
    end
  end

  # Deleting a product, or an org with its products, leaves the devices and
  # their certificates and keys where they were.
  describe "authenticate/2 once the device, its product or its org is deleted" do
    setup %{org: org, user: user, tmp_dir: tmp_dir} do
      product = Fixtures.product_fixture(user, org, %{name: "deleted_later"})
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
      device = Fixtures.device_fixture(org, product, firmware)
      %{cert: cert} = Fixtures.device_certificate_fixture(device, X509.PrivateKey.new_ec(:secp256r1))
      {:ok, device_key} = Devices.create_shared_secret_auth(device)
      {:ok, product_key} = Products.create_shared_secret_auth(product)

      %{
        product: product,
        firmware: firmware,
        device: device,
        cert: {:ssl_cert, X509.Certificate.to_der(cert)},
        device_key: {:shared_secret, Map.new(Utils.nh1_key_secret_headers(device_key, device.identifier))},
        product_key: {:shared_secret, Map.new(Utils.nh1_key_secret_headers(product_key, device.identifier))}
      }
    end

    test "refuses the device however it authenticates once its org is deleted, and says why", context do
      {:ok, _} = Accounts.soft_delete_org(context.org)

      ref = :telemetry_test.attach_event_handlers(self(), [[:nerves_hub, :devices, :invalid_auth]])

      for credentials <- [context.cert, context.device_key, context.product_key] do
        assert {:error, :invalid_auth} = Authentication.authenticate(credentials)
      end

      identifier = context.device.identifier

      # The product key already stopped working with its product.
      for _ <- [:cert, :device_key] do
        assert_received {[:nerves_hub, :devices, :invalid_auth], ^ref, _, %{reason: :deleted, identifier: ^identifier}}
      end

      assert %{status: :registered} = Repo.reload!(context.device)
    end

    test "refuses the device once its product is deleted, and not the org's other devices", context do
      other_product = Fixtures.product_fixture(context.user, context.org, %{name: "still_here"})
      other_device = Fixtures.device_fixture(context.org, other_product, context.firmware)
      %{cert: other_cert} = Fixtures.device_certificate_fixture(other_device, X509.PrivateKey.new_ec(:secp256r1))

      {:ok, _} = Products.delete_product(context.product)

      for credentials <- [context.cert, context.device_key, context.product_key] do
        assert {:error, :invalid_auth} = Authentication.authenticate(credentials)
      end

      assert {:ok, %{device_id: other_device_id}} =
               Authentication.authenticate({:ssl_cert, X509.Certificate.to_der(other_cert)})

      assert other_device_id == other_device.id
    end

    # Deleting a device removes its certificates, and the TLS handshake turns a
    # deleted device away, but neither is the socket's own check.
    test "refuses a deleted device whose certificate is still on record", context do
      context.device
      |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second))
      |> Repo.update!()

      assert {:error, :invalid_auth} = Authentication.authenticate(context.cert)
    end
  end

  describe "authenticate/1 with a shared secret" do
    # Every salt carries its signing time, so a cached key is never reused and
    # the table only grows. On a device node that was 150,917 rows in 12 days.
    test "leaves no derived key in Plug.Crypto's cache", %{auth: auth} do
      identifier = Ecto.UUID.generate()

      # The helper signs through Plug.Crypto too, which would cache the very
      # key this test looks for.
      headers = Map.new(Utils.nh1_key_secret_headers(auth, identifier, cache: nil))

      assert {:ok, %{device_identifier: ^identifier}} =
               Authentication.authenticate({:shared_secret, headers})

      assert :ets.match_object(Keys, {{auth.secret, :_, :_, :_, :_}, :_}) == []
    end
  end
end
