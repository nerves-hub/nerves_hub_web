defmodule NervesHubWeb.UserConsoleChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHubWeb.APISocket
  alias NervesHubWeb.UserConsoleChannel

  describe "API Token : join/3" do
    test "authorized users can join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(
                 socket,
                 UserConsoleChannel,
                 "user:console:identifier-#{device.identifier}"
               )
    end

    test "unauthorized user cannot join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      # Connect with unauthorized user's token
      {:ok, socket} = connect(APISocket, %{"token" => other_user_token})

      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 UserConsoleChannel,
                 "user:console:identifier-#{device.identifier}"
               )
    end
  end

  defp device_fixture(user, device_params, tmp_dir) do
    org = Fixtures.org_fixture(user)
    {:ok, org_user} = Accounts.get_org_user(org, user)

    # Use the lowest permissioned org user possible for the channel.
    {:ok, _updated_org_user} = Accounts.change_org_user_role(org_user, :manage)

    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: tmp_dir
      })

    Fixtures.device_fixture(
      org,
      product,
      firmware,
      device_params
    )
  end
end
