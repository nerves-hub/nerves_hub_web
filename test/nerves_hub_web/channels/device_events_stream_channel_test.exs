defmodule NervesHubWeb.DeviceEventsStreamChannelTest do
  use NervesHubWeb.ChannelCase

  alias NervesHub.Accounts
  alias NervesHub.Fixtures
  alias NervesHubWeb.DeviceEventsStreamChannel
  alias NervesHubWeb.EventStreamSocket

  describe "handle_info/2" do
    test "handles fwup_progress messages" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      {:ok, _join_reply, _channel} =
        subscribe_and_join(socket, DeviceEventsStreamChannel, "device:#{device.identifier}")

      NervesHubWeb.Endpoint.broadcast("device:#{device.identifier}:internal", "fwup_progress", %{
        percent: 50
      })

      assert_push("firmware_update", %{percent: 50})
    end

    test "handles console messages" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      {:ok, _join_reply, _channel} =
        subscribe_and_join(
          socket,
          DeviceEventsStreamChannel,
          "device:console:#{device.identifier}"
        )

      NervesHubWeb.Endpoint.broadcast("user:console:#{device.id}", "up", %{"data" => "u"})
      assert_push("console_raw", %{data: "u"})
      msg = %{"event" => "foo", "name" => "bar"}
      NervesHubWeb.Endpoint.broadcast("user:console:#{device.id}", "message", msg)
      assert_push("console_message", ^msg)
    end
  end

  describe "join/3" do
    test "authorized users can join the device channel" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:#{device.identifier}"
               )
    end

    test "unauthorized user cannot join the device channel" do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-456"})

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

    test "authorized users can join the console channel" do
      user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-123"})

      user_token = Accounts.create_user_api_token(user, "test-token")

      {:ok, socket} = connect(EventStreamSocket, %{"token" => user_token})

      assert {:ok, _reply, _channel} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:console:#{device.identifier}"
               )
    end

    test "unauthorized user cannot join the console channel" do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()

      device = device_fixture(user, %{identifier: "test-device-456"})

      other_user_token = Accounts.create_user_api_token(other_user, "test-token")

      # Connect with unauthorized user's token
      {:ok, socket} = connect(EventStreamSocket, %{"token" => other_user_token})

      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 DeviceEventsStreamChannel,
                 "device:console:#{device.identifier}"
               )
    end
  end

  defp device_fixture(user, device_params) do
    org = Fixtures.org_fixture(user)
    {:ok, org_user} = Accounts.get_org_user(org, user)

    # Use the lowest permissioned org user possible for the channel.
    {:ok, _updated_org_user} = Accounts.change_org_user_role(org_user, :view)

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
