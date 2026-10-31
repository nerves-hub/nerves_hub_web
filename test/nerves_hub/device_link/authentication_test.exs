defmodule NervesHub.DeviceLink.AuthenticationTest do
  # Not async: shared secrets are switched on through application env.
  use NervesHub.DataCase

  alias NervesHub.Accounts
  alias NervesHub.DeviceLink.Authentication
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
