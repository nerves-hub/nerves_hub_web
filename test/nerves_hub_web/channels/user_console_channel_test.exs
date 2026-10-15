defmodule NervesHubWeb.UserConsoleChannelTest do
  use NervesHubWeb.ChannelCase
  use AssertEventually, timeout: 1000, interval: 20

  alias NervesHub.Accounts
  alias NervesHub.Consoles.PubSub
  alias NervesHub.Fixtures
  alias NervesHubWeb.APISocket
  alias NervesHubWeb.UserConsoleChannel
  alias Phoenix.Socket.Broadcast

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

      {:ok, socket} = connect(APISocket, %{"token" => other_user_token})

      assert {:error, %{reason: _reason}} =
               subscribe_and_join(
                 socket,
                 UserConsoleChannel,
                 "user:console:identifier-#{device.identifier}"
               )
    end
  end

  describe "handle_in" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      device = device_fixture(user, %{identifier: "console-test-device"}, tmp_dir)
      user_token = Accounts.create_user_api_token(user, "test-token")
      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserConsoleChannel, "user:console:identifier-#{device.identifier}")

      %{channel: channel, user_name: user.name}
    end

    test "message event broadcasts to the channel", %{channel: channel, user_name: name} do
      push(channel, "message", %{"data" => "hello"})
      assert_broadcast("message", %{name: ^name})
    end

    # These events are forwarded to the device console channel, which the test
    # process doesn't subscribe to. The only testable property from this side is
    # that the channel process handles them without crashing.
    test "file-data/start event does not crash the channel", %{channel: channel} do
      push(channel, "file-data/start", %{"filename" => "test.txt"})
      refute_receive {:error, _}, 100
    end

    test "file-data event does not crash the channel", %{channel: channel} do
      push(channel, "file-data", %{"chunk" => "abc"})
      refute_receive {:error, _}, 100
    end

    test "file-data/stop event does not crash the channel", %{channel: channel} do
      push(channel, "file-data/stop", %{"filename" => "test.txt"})
      refute_receive {:error, _}, 100
    end

    test "unknown events do not crash the channel", %{channel: channel} do
      push(channel, "phx_ctrl_c", %{})
      refute_receive {:error, _}, 100
    end
  end

  describe "talking to the device's console" do
    setup %{tmp_dir: tmp_dir} do
      user = Fixtures.user_fixture()
      device = device_fixture(user, %{identifier: "console-route-device"}, tmp_dir)
      user_token = Accounts.create_user_api_token(user, "test-token")
      {:ok, socket} = connect(APISocket, %{"token" => user_token})

      %{socket: socket, device: device, user: user}
    end

    test "joining asks the device's console to connect", %{socket: socket, device: device} do
      # Stand in for the device-side console channel.
      :ok = PubSub.subscribe_console(device.id)

      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserConsoleChannel, "user:console:identifier-#{device.identifier}")

      assert_receive {:connect, pid}, 500
      assert pid == channel.channel_pid
    end

    test "input goes straight to the console that answered", %{socket: socket, device: device} do
      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserConsoleChannel, "user:console:identifier-#{device.identifier}")

      # Answer as the console would. This process never subscribes to the
      # console's topic, so input can only reach it by being sent here directly.
      send(channel.channel_pid, {:metadata, self(), %{version: "1.0.0"}})
      assert_push("metadata", %{version: "1.0.0"})

      push(channel, "dn", %{"data" => "x"})

      assert_receive %Broadcast{event: "dn", payload: %{"data" => "x"}}, 500
    end

    test "input is broadcast again once the console goes away", %{socket: socket, device: device} do
      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserConsoleChannel, "user:console:identifier-#{device.identifier}")

      console = spawn(fn -> receive(do: (:stop -> :ok)) end)
      send(channel.channel_pid, {:metadata, console, %{version: "1.0.0"}})
      assert_push("metadata", _)

      ref = Process.monitor(console)
      send(console, :stop)
      assert_receive {:DOWN, ^ref, :process, ^console, _}

      assert_eventually(is_nil(:sys.get_state(channel.channel_pid).assigns.console))

      # A console that came back, on whichever node, hears it through its topic.
      :ok = PubSub.subscribe_console(device.id)
      push(channel, "dn", %{"data" => "y"})

      assert_receive %Broadcast{event: "dn", payload: %{"data" => "y"}}, 500
    end

    test "uploads are announced to the device page", %{socket: socket, device: device, user: user} do
      :ok = PubSub.subscribe_console_watcher(device.id)

      {:ok, _reply, channel} =
        subscribe_and_join(socket, UserConsoleChannel, "user:console:identifier-#{device.identifier}")

      push(channel, "file-data/start", %{"filename" => "test.txt"})
      push(channel, "file-data", %{"chunk" => "abc"})
      push(channel, "file-data/stop", %{"filename" => "test.txt"})

      user_id = user.id
      assert_receive %Broadcast{event: "file-data/start", payload: %{uploaded_by: ^user_id}}, 500
      assert_receive %Broadcast{event: "file-data/stop", payload: %{uploaded_by: ^user_id}}, 500
      refute_received %Broadcast{event: "file-data"}
    end
  end

  defp device_fixture(user, device_params, tmp_dir) do
    org = Fixtures.org_fixture(user)
    {:ok, org_user} = Accounts.get_org_user(org, user)
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
