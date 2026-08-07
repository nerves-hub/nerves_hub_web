defmodule NervesHubWeb.DeviceEventsStreamChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Devices.PubSub
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceEventsStreamChannel
  alias NervesHubWeb.EventStreamSocket

  describe "handle_info/2" do
    test "forwards firmware update progress to subscribers", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      {:ok, _join_reply, _channel} =
        subscribe_and_join(socket, DeviceEventsStreamChannel, "device:#{device.identifier}")

      # Go through the real broadcast path rather than hand-rolling the message,
      # so that a mismatch between what is broadcast and what is handled fails
      # this test instead of hiding behind it.
      :ok = FirmwareUpdates.update_inflight_update(device.id, "downloading", 50, false)

      assert_push("firmware_update", %{percent: 50, stage: "downloading"})
    end
  end

  describe "join/3" do
    test "authorized users can join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:#{device.identifier}"
               )
    end

    test "unauthorized user cannot join the device channel", %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"}, tmp_dir)

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      # Connect with unauthorized user's token
      {:ok, socket} = connect(EventStreamSocket, %{"token" => other_user_token})

      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:#{device.identifier}"
               )
    end
  end

  defp device_fixture(user, device_params, tmp_dir) do
    org = Fixtures.org_fixture(user)
    {:ok, org_user} = Accounts.get_org_user(org, user)

    # Use the lowest permissioned org user possible for the channel.
    {:ok, _updated_org_user} = Accounts.change_org_user_role(org_user, :view)

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
