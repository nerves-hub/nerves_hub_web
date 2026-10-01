defmodule NervesHub.DeviceLink.AuthenticationTest do
  # Not async: shared secrets are switched on through application env.
  use NervesHub.DataCase

  alias NervesHub.DeviceLink.Authentication
  alias NervesHub.Fixtures
  alias NervesHub.Products
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

    %{auth: auth}
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
