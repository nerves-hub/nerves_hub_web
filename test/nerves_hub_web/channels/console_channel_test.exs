defmodule NervesHubWeb.ConsoleChannelTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks

  alias NervesHub.Consoles.PubSub, as: ConsolePubSub
  alias NervesHub.Fixtures
  alias NervesHubWeb.ConsoleChannel
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias Phoenix.Socket.Broadcast

  defp build_socket(tmp_dir) do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    firmware =
      Fixtures.firmware_fixture(org_key, product, %{
        version: "0.0.1",
        dir: tmp_dir
      })

    _deployment_group = Fixtures.deployment_group_fixture(firmware, %{user: user})
    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})
    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    params = %{"device_api_version" => "2.2.0"}

    {:ok, _, _device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    assert_push("extensions:get", _)

    {socket, device}
  end

  describe "join/3" do
    test "joins the console channel with current_line and buffer assigns", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      state = :sys.get_state(console_channel.channel_pid)

      assert state.assigns.scrollback.current_line == ""
      assert state.assigns.scrollback.buffer != nil

      close_cleanly(console_channel)
    end

    test "registers device in console group (console_active?)", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      # Wait for after_join to complete
      _state = :sys.get_state(console_channel.channel_pid)

      assert ConsolePubSub.console_active?(device.id)

      close_cleanly(console_channel)
    end

    test "stores console_version in assigns after after_join", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.2.3"})

      state = :sys.get_state(console_channel.channel_pid)

      assert state.assigns.version == "1.2.3"

      close_cleanly(console_channel)
    end
  end

  describe "handle_in up" do
    test "broadcasts up event to user-console subscribers", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      ConsolePubSub.subscribe_user_console(device.id)

      push(console_channel, "up", %{"data" => "hello from device\n"})

      assert_receive %Broadcast{event: "up", payload: %{"data" => "hello from device\n"}}, 500

      close_cleanly(console_channel)
    end

    test "appends data to current_line and splits on newlines", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      push(console_channel, "up", %{"data" => "line1\nline2\npartial"})
      state = :sys.get_state(console_channel.channel_pid)

      assert String.ends_with?(state.assigns.scrollback.current_line, "partial")

      close_cleanly(console_channel)
    end

    test "inserts completed lines into the circular buffer", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      push(console_channel, "up", %{"data" => "complete line\n"})
      state = :sys.get_state(console_channel.channel_pid)

      buf_contents = Enum.join(state.assigns.scrollback.buffer)
      assert String.contains?(buf_contents, "complete line")

      close_cleanly(console_channel)
    end
  end

  describe "handle_in file-data events" do
    test "file-data/start broadcasts to user console", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      ConsolePubSub.subscribe_user_console(device.id)

      push(console_channel, "file-data/start", %{"filename" => "test.txt"})

      assert_receive %Broadcast{event: "file-data/start", payload: %{"filename" => "test.txt"}}, 500

      close_cleanly(console_channel)
    end

    test "file-data broadcasts chunk to user console", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      ConsolePubSub.subscribe_user_console(device.id)

      push(console_channel, "file-data", %{"chunk" => "aGVsbG8="})

      assert_receive %Broadcast{event: "file-data", payload: %{"chunk" => "aGVsbG8="}}, 500

      close_cleanly(console_channel)
    end

    test "file-data/stop broadcasts to user console", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      ConsolePubSub.subscribe_user_console(device.id)

      push(console_channel, "file-data/stop", %{})

      assert_receive %Broadcast{event: "file-data/stop", payload: %{}}, 500

      close_cleanly(console_channel)
    end
  end

  describe "handle_info :connect" do
    test "sends {:metadata, metadata} and {:cache, lines} to connecting pid", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "2.0.0"})

      push(console_channel, "up", %{"data" => "some output\n"})
      _state = :sys.get_state(console_channel.channel_pid)

      send(console_channel.channel_pid, {:connect, self()})

      assert_receive {:metadata, %{version: "2.0.0"}}, 500
      assert_receive {:cache, _lines}, 500

      close_cleanly(console_channel)
    end
  end

  describe "handle_info Broadcast" do
    test "pushes broadcast event to the socket", %{tmp_dir: tmp_dir} do
      {socket, device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      _state = :sys.get_state(console_channel.channel_pid)

      # Broadcasts routed to handle_info must have a different topic than "console"
      # (Phoenix.Channel.Server only calls handle_out for broadcasts matching the socket topic)
      send(
        console_channel.channel_pid,
        %Broadcast{topic: "user:console:#{device.id}", event: "dn", payload: %{"data" => "input"}}
      )

      assert_push("dn", %{"data" => "input"})

      close_cleanly(console_channel)
    end
  end

  describe "terminate/2" do
    test "returns {:shutdown, :closed}", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_socket(tmp_dir)

      {:ok, %{}, console_channel} =
        subscribe_and_join(socket, ConsoleChannel, "console", %{"console_version" => "1.0.0"})

      state = :sys.get_state(console_channel.channel_pid)

      result = ConsoleChannel.terminate(:shutdown, state)

      assert result == {:shutdown, :closed}

      close_cleanly(console_channel)
    end
  end
end
