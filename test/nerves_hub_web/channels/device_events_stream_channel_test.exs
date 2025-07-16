defmodule NervesHubWeb.DeviceEventsStreamChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Fixtures
  alias NervesHub.Accounts
  alias NervesHubWeb.EventStreamSocket
  alias NervesHubWeb.DeviceEventsStreamChannel

  describe "handle_info/2" do
    test "handles fwup_progress messages" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      {:ok, _join_reply, _channel} =
        subscribe_and_join(socket, DeviceEventsStreamChannel, "device:#{device.identifier}")

      # Broadcast a firmware update
      NervesHubWeb.Endpoint.broadcast("device:#{device.identifier}:internal", "fwup_progress", %{
        percent: 50
      })

      # Assert that the channel receives the firmware update message
      assert_push("firmware_update", %{percent: 50})
    end

    test "unauthorized user cannot join the device channel" do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-456"})

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      # Connect with unauthorized user's token
      {:ok, socket} = connect(EventStreamSocket, %{"token" => other_user_token})

      # Attempt to join should fail
      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:#{device.identifier}"
               )
    end

    test "missing token prevents joining" do
      assert {:error, :no_token} == connect(EventStreamSocket, %{})
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
