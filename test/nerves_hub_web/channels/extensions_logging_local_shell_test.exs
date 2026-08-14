defmodule NervesHubWeb.Extensions.LoggingLocalShellTest do
  use NervesHubWeb.ChannelCase
  use DefaultMocks
  use Mimic

  alias NervesHub.Consoles.PubSub, as: ConsolePubSub
  alias NervesHub.Devices.LogLines
  alias NervesHub.Extensions.LocalShell
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.RateLimit.LogLines, as: RateLimit
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  alias Phoenix.Socket.Broadcast

  setup do
    original = Application.get_env(:nerves_hub, :analytics_enabled)
    Application.put_env(:nerves_hub, :analytics_enabled, true)

    on_exit(fn ->
      Application.put_env(:nerves_hub, :analytics_enabled, original)
    end)
  end

  # ---- Helpers ----

  defp build_connected_socket(tmp_dir, opts \\ []) do
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

    if Keyword.get(opts, :enable_local_shell, false) do
      Products.enable_extension_setting(product, "local_shell")
    end

    device = Fixtures.device_fixture(org, product, firmware, %{tags: ["beta"]})
    %{db_cert: certificate} = Fixtures.device_certificate_fixture(device)

    {:ok, socket} =
      connect(DeviceSocket, %{}, connect_info: %{peer_data: %{ssl_cert: certificate.der}})

    params = %{"device_api_version" => "2.2.0"}

    {:ok, _, _device_channel} =
      subscribe_and_join(socket, DeviceChannel, "device:#{device.id}", params)

    # Consume the extensions:get push from device channel join so it doesn't
    # pollute later assertions.
    assert_push("extensions:get", _)

    {socket, device}
  end

  defp join_extensions(socket, extension_versions) do
    params = Map.merge(%{"device_api_version" => "2.2.0"}, extension_versions)
    {:ok, _attach_list, ext_channel} = subscribe_and_join(socket, ExtensionsChannel, "extensions", params)
    ext_channel
  end

  defp attach_extension(ext_channel, name) do
    push(ext_channel, "#{name}:attached", %{})
    :sys.get_state(ext_channel.channel_pid)
  end

  # ---- Extensions.Logging ----

  describe "Extensions.Logging handle_in send — rate limit allows" do
    test "calls LogLines.async_create when rate limit allows", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"logging" => "0.0.1"})
      attach_extension(ext_channel, "logging")

      test_pid = self()

      stub(RateLimit, :hit, fn _key, _tokens_per_sec, _max, _cost -> {:allow, 9} end)

      expect(LogLines, :async_create, fn _device_info, log_line ->
        send(test_pid, {:log_created, log_line})
        {:ok, %{}}
      end)

      allow(RateLimit, self(), ext_channel.channel_pid)
      allow(LogLines, self(), ext_channel.channel_pid)

      log_payload = %{
        "timestamp" => "2025-01-01T00:00:00.000000Z",
        "level" => "info",
        "message" => "hello from device",
        "meta" => %{}
      }

      push(ext_channel, "logging:send", log_payload)

      assert_receive {:log_created, ^log_payload}, 500

      close_cleanly(ext_channel)
    end

    test "does not call LogLines.async_create when rate limit denies", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"logging" => "0.0.1"})
      attach_extension(ext_channel, "logging")

      stub(RateLimit, :hit, fn _key, _tokens_per_sec, _max, _cost -> {:deny, 100} end)
      reject(LogLines, :async_create, 2)

      allow(RateLimit, self(), ext_channel.channel_pid)
      allow(LogLines, self(), ext_channel.channel_pid)

      push(ext_channel, "logging:send", %{
        "timestamp" => "2025-01-01T00:00:00.000000Z",
        "level" => "warn",
        "message" => "throttled",
        "meta" => %{}
      })

      # Synchronize — if async_create were called, Mimic would fail
      :sys.get_state(ext_channel.channel_pid)

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.Logging attach/detach" do
    test "attach returns {:noreply, socket} without pushing extra events", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"logging" => "0.0.1"})

      push(ext_channel, "logging:attached", %{})
      :sys.get_state(ext_channel.channel_pid)

      # Nothing extra pushed after attaching logging
      refute_push("logging:*", _)

      close_cleanly(ext_channel)
    end

    test "detach returns {:noreply, socket}", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"logging" => "0.0.1"})
      attach_extension(ext_channel, "logging")

      push(ext_channel, "logging:detached", %{})
      :sys.get_state(ext_channel.channel_pid)

      refute_push("logging:*", _)

      close_cleanly(ext_channel)
    end

    test "unhandled handle_info messages are ignored and channel stays alive", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir)
      ext_channel = join_extensions(socket, %{"logging" => "0.0.1"})
      attach_extension(ext_channel, "logging")

      send(ext_channel.channel_pid, :unexpected_msg_for_logging)
      :sys.get_state(ext_channel.channel_pid)

      assert Process.alive?(ext_channel.channel_pid)

      close_cleanly(ext_channel)
    end
  end

  # ---- Extensions.LocalShell ----

  describe "Extensions.LocalShell attach" do
    test "pushes local_shell:request_shell and joins the local-shell group", %{tmp_dir: tmp_dir} do
      {socket, device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})

      push(ext_channel, "local_shell:attached", %{})
      :sys.get_state(ext_channel.channel_pid)

      assert_push("local_shell:request_shell", %{})
      assert ConsolePubSub.local_shell_active?(device.id)

      close_cleanly(ext_channel)
    end

    test "initializes current_line and buffer assigns on attach", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})

      push(ext_channel, "local_shell:attached", %{})
      state = :sys.get_state(ext_channel.channel_pid)

      assert state.assigns.current_line == ""
      assert state.assigns.buffer != nil

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.LocalShell detach" do
    test "leaves the local-shell group and nils the assigns", %{tmp_dir: tmp_dir} do
      {socket, device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})
      attach_extension(ext_channel, "local_shell")

      push(ext_channel, "local_shell:detached", %{})
      :sys.get_state(ext_channel.channel_pid)

      refute ConsolePubSub.local_shell_active?(device.id)

      state = :sys.get_state(ext_channel.channel_pid)
      assert is_nil(state.assigns.current_line)
      assert is_nil(state.assigns.buffer)

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.LocalShell handle_in shell_output" do
    test "broadcasts output to user local-shell subscribers", %{tmp_dir: tmp_dir} do
      {socket, device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})
      attach_extension(ext_channel, "local_shell")

      ConsolePubSub.subscribe_user_local_shell(device.id)

      push(ext_channel, "local_shell:shell_output", %{"data" => "hello\n"})

      assert_receive %Broadcast{event: "output", payload: %{data: "hello\n"}}, 500

      close_cleanly(ext_channel)
    end

    test "appends data without trailing newline to current_line", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})
      attach_extension(ext_channel, "local_shell")

      push(ext_channel, "local_shell:shell_output", %{"data" => "line1\nline2\npartial"})
      state = :sys.get_state(ext_channel.channel_pid)

      # "partial" (last segment without trailing newline) stays as current_line
      assert String.ends_with?(state.assigns.current_line, "partial")

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.LocalShell handle_info :connect" do
    test "sends {:cache, lines} to the connecting pid", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})
      attach_extension(ext_channel, "local_shell")

      push(ext_channel, "local_shell:shell_output", %{"data" => "buffered line\n"})
      :sys.get_state(ext_channel.channel_pid)

      # Route {:connect, pid} via the ExtensionsChannel tuple routing
      send(ext_channel.channel_pid, {LocalShell, {:connect, self()}})

      assert_receive {:cache, _lines}, 500

      close_cleanly(ext_channel)
    end
  end

  describe "Extensions.LocalShell unknown handle_in" do
    test "unknown event is handled without crash", %{tmp_dir: tmp_dir} do
      {socket, _device} = build_connected_socket(tmp_dir, enable_local_shell: true)
      ext_channel = join_extensions(socket, %{"local_shell" => "0.0.1"})
      attach_extension(ext_channel, "local_shell")

      push(ext_channel, "local_shell:unknown_event", %{"data" => "whatever"})
      :sys.get_state(ext_channel.channel_pid)

      assert Process.alive?(ext_channel.channel_pid)

      close_cleanly(ext_channel)
    end
  end
end
