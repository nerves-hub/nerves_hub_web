defmodule NervesHubWeb.ExternalDeviceListenerChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Fixtures
  alias NervesHub.Accounts
  alias NervesHubWeb.APISocket
  alias NervesHubWeb.ExternalDeviceListenerChannel

  describe "broadcast_firmware_update/2" do
    test "causes all subscribers to receive firmware updates" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      {:ok, _join_reply, _channel} =
        subscribe_and_join(socket, ExternalDeviceListenerChannel, "device:#{device.identifier}")

      # Broadcast a firmware update
      ExternalDeviceListenerChannel.broadcast_firmware_update(device, 50)

      # Assert that the channel receives the firmware update message
      assert_push("firmware_update", %{percent: 50})
    end

    test "unauthorized user cannot join device channel" do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-456"})

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      # Connect with unauthorized user's token
      {:ok, socket} = connect(APISocket, %{"token" => other_user_token})

      # Attempt to join should fail
      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 ExternalDeviceListenerChannel,
                 "device:#{device.identifier}"
               )
    end

    test "missing token prevents joining" do
      assert {:error, :no_token} == connect(APISocket, %{})
    end
  end

  defp device_fixture(user, device_params) do
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1"
      })

    Fixtures.device_fixture(
      org,
      product,
      firmware,
      device_params
    )
  end
end
