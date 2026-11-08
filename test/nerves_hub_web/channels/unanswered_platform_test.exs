defmodule NervesHubWeb.UnansweredPlatformTest.StubPlatform do
  @moduledoc """
  Answers DeviceLink calls in place of the platform, installed as the dispatcher.

  So a test can raise exactly what the remote dispatcher raises, from exactly
  where it raises it, without a second node. Every call is reported to the test
  as `{:platform_call, function, args}`; `overrides` maps a function to what it
  should do instead of the default answer.
  """

  @behaviour NervesHub.DeviceLink.Dispatcher

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Dispatcher
  alias NervesHub.DeviceLink.Session

  @handler_key :unanswered_platform_test_handler
  @connection_ref "019ff994-e08c-774f-a167-7e5473422e5c"

  def install(test_pid, overrides \\ %{}) do
    handler = fn function, args ->
      send(test_pid, {:platform_call, function, args})

      case Map.get(overrides, function) do
        nil -> default(function, args)
        fun -> fun.(args)
      end
    end

    previous = Application.get_env(:nerves_hub, Dispatcher)

    Application.put_env(:nerves_hub, @handler_key, handler)
    Application.put_env(:nerves_hub, Dispatcher, __MODULE__)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:nerves_hub, @handler_key)

      if previous,
        do: Application.put_env(:nerves_hub, Dispatcher, previous),
        else: Application.delete_env(:nerves_hub, Dispatcher)
    end)

    :ok
  end

  @impl Dispatcher
  def call(function, args), do: Application.fetch_env!(:nerves_hub, @handler_key).(function, args)

  defp default(:authenticate, _args), do: {:ok, device_info()}
  defp default(:connect, [info, _ip_address]), do: {:ok, %{info | connection_ref: @connection_ref}}
  defp default(:heartbeat, _args), do: :ok
  defp default(:disconnect, _args), do: :ok
  defp default(:device_join, [info, _params]), do: {:ok, %Session{device_info: info}, []}

  defp default(function, [session | _]) when function in [:device_message, :device_notify, :device_broadcast],
    do: {session, []}

  defp default(:extensions_join, _args), do: {[], %{}}

  defp default(function, [extensions | _]) when function in [:extension_message, :extension_info],
    do: {:ok, extensions, []}

  defp device_info() do
    %DeviceInfo{
      allowed_extensions: [:health, :geo, :logging, :local_shell],
      device_id: 1234,
      device_identifier: "test-device",
      device_update_mode: :automatic,
      device_updates_enabled: true,
      managed_updates_allowed: false,
      firmware_metadata: %{uuid: "b7d3f5b2-0000-4000-8000-000000000001", version: "1.0.0"},
      org_id: 1,
      product_id: 2
    }
  end
end

defmodule NervesHubWeb.UnansweredPlatformTest do
  @moduledoc """
  A platform that does not answer costs a device one message, not its connection.

  The platform fails to answer in two ways that say nothing about the device:
  no node can be reached (`NoHandlersError`), or the node that took the call is
  slow (`TimeoutError`). Both used to end the process holding the connection,
  and the device rebuilt it and asked again -- more load, at the moment the
  platform was shortest of it. Here each one is raised from the stub platform,
  exactly where the dispatcher would raise it.
  """

  use NervesHubWeb.ChannelCase

  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.TimeoutError
  alias NervesHubWeb.Channels.DeviceJSONSerializer
  alias NervesHubWeb.DeviceChannel
  alias NervesHubWeb.DeviceSocket
  alias NervesHubWeb.ExtensionsChannel
  alias NervesHubWeb.UnansweredPlatformTest.StubPlatform

  @moduletag :capture_log

  @reasons [:timeout, :no_handlers]

  setup do
    :ok = StubPlatform.install(self())
    attach_unanswered()
    :ok
  end

  for reason <- @reasons do
    describe "the extensions channel, when the platform #{reason}" do
      @describetag reason: reason

      test "drops the message and keeps the extensions it had", %{reason: reason} do
        answer =
          answer_after_first_failure(reason, :extension_message, fn [_extensions | _] ->
            {:ok, %{"health" => :after}, [{:push, "health:check", %{}}]}
          end)

        StubPlatform.install(self(), %{
          extensions_join: fn _ -> {["health"], %{"health" => :before}} end,
          extension_message: answer
        })

        {:ok, socket} = connect_device()
        {:ok, _reply, channel} = subscribe_and_join(socket, ExtensionsChannel, "extensions", %{})

        push(channel, "health:report", %{})
        assert_receive {:platform_call, :extension_message, _}, 1_000

        assert extensions(channel) == %{"health" => :before}
        refute_push("health:check", _)
        assert_unanswered(:extension_message, reason)

        # The channel is still there, and the next message is answered.
        push(channel, "health:report", %{})
        assert_push("health:check", %{})
        assert extensions(channel) == %{"health" => :after}
      end

      test "drops a timer delivery, and the timer keeps firing", %{reason: reason} do
        StubPlatform.install(self(), %{
          extensions_join: fn _ -> {["health"], %{"health" => :before}} end,
          extension_message: fn [extensions | _] ->
            {:ok, extensions, [{:start_timer, {"health", :check}, {Health, :check}, 20}]}
          end,
          extension_info: fn _ -> unanswered(reason, :extension_info) end
        })

        {:ok, socket} = connect_device()
        {:ok, _reply, channel} = subscribe_and_join(socket, ExtensionsChannel, "extensions", %{})

        push(channel, "health:attached", %{})

        assert_receive {:platform_call, :extension_info, [_, Health, :check]}, 1_000
        assert_receive {:platform_call, :extension_info, [_, Health, :check]}, 1_000

        assert Process.alive?(channel.channel_pid)
        assert extensions(channel) == %{"health" => :before}
        assert_unanswered(:extension_info, reason)
      end

      test "refuses the join, and the socket stays usable", %{reason: reason} do
        StubPlatform.install(self(), %{
          extensions_join: fn _ -> unanswered(reason, :extensions_join) end
        })

        {:ok, socket} = connect_device()

        assert {:error, %{error: "could not connect"}} =
                 subscribe_and_join(socket, ExtensionsChannel, "extensions", %{})

        assert_unanswered(:extensions_join, reason)

        assert {:ok, _reply, _channel} =
                 subscribe_and_join(socket, DeviceChannel, "device:1234", %{})
      end
    end

    describe "the device channel, when the platform #{reason}" do
      @describetag reason: reason

      test "drops a message, a notification and a broadcast, and keeps the session",
           %{reason: reason} do
        StubPlatform.install(self(), %{
          device_message: fn _ -> unanswered(reason, :device_message) end,
          device_notify: fn _ -> unanswered(reason, :device_notify) end,
          device_broadcast: fn _ -> unanswered(reason, :device_broadcast) end
        })

        {:ok, socket} = connect_device()
        {:ok, _reply, channel} = subscribe_and_join(socket, DeviceChannel, "device:1234", %{})
        session = session(channel)

        push(channel, "status_update", %{"status" => "updating"})
        assert_receive {:platform_call, :device_message, _}, 1_000
        assert_unanswered(:device_message, reason)

        send(channel.channel_pid, :something_for_the_device)
        assert_receive {:platform_call, :device_notify, _}, 1_000
        assert_unanswered(:device_notify, reason)

        @endpoint.broadcast!("device:1234", "updated", %{})
        assert_receive {:platform_call, :device_broadcast, _}, 1_000
        assert_unanswered(:device_broadcast, reason)

        assert session(channel) == session
      end

      test "refuses the join", %{reason: reason} do
        StubPlatform.install(self(), %{device_join: fn _ -> unanswered(reason, :device_join) end})

        {:ok, socket} = connect_device()

        assert {:error, %{error: "could not connect"}} =
                 subscribe_and_join(socket, DeviceChannel, "device:1234", %{})

        assert_unanswered(:device_join, reason)
      end
    end

    describe "the socket, when the platform #{reason}" do
      @describetag reason: reason

      test "keeps the connection when a heartbeat goes unanswered", %{reason: reason} do
        StubPlatform.install(self(), %{heartbeat: fn _ -> unanswered(reason, :heartbeat) end})

        {channels, socket} = websocket()
        long_ago = System.monotonic_time(:second) - to_timeout(day: 1)
        socket = Phoenix.Socket.assign(socket, :last_heartbeat, long_ago)

        frame = {Jason.encode!([nil, "1", "phoenix", "heartbeat", %{}]), opcode: :text}

        assert {:reply, :ok, _reply, {_channels, socket}} =
                 DeviceSocket.handle_in(frame, {channels, socket})

        assert_received {:platform_call, :heartbeat, _}
        assert_unanswered(:heartbeat, reason)

        # Counted as done: asking again on every frame would only add load while
        # the platform is slow.
        assert socket.assigns.last_heartbeat > long_ago
      end

      test "finishes disconnecting when the disconnect goes unanswered", %{reason: reason} do
        StubPlatform.install(self(), %{disconnect: fn _ -> unanswered(reason, :disconnect) end})

        {:ok, socket} = connect_device()

        DeviceSocket.terminate({:error, :closed}, {%{}, socket})

        assert_received {:platform_call, :disconnect, _}
        assert_unanswered(:disconnect, reason)
      end

      test "still refuses a device it cannot authenticate", %{reason: reason} do
        StubPlatform.install(self(), %{
          authenticate: fn _ -> unanswered(reason, :authenticate) end
        })

        assert {:error, :platform_unavailable} = connect_device()
      end
    end
  end

  # ------------------------------------------------------------------ helpers

  defp unanswered(:timeout, function),
    do: raise(TimeoutError, function: function, node: :"web@10.0.0.1", timeout: 5_000)

  defp unanswered(:no_handlers, function), do: raise(NoHandlersError, function: function)

  # Fails the first call, answers every one after it.
  defp answer_after_first_failure(reason, function, answer) do
    calls = start_supervised!({Agent, fn -> 0 end})

    fn args ->
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> unanswered(reason, function)
        _ -> answer.(args)
      end
    end
  end

  defp connect_device() do
    connect(DeviceSocket, %{}, connect_info: %{x_headers: [{"x-nh-key", "nhd_test"}, {"x-nh-signature", "sig"}]})
  end

  # The socket as the transport holds it, which Phoenix.ChannelTest never builds.
  defp websocket() do
    {:ok, state} =
      DeviceSocket.connect(%{
        endpoint: @endpoint,
        transport: :websocket,
        options: [serializer: [{DeviceJSONSerializer, "~> 2.0.0"}]],
        params: %{"vsn" => "2.0.0"},
        connect_info: %{x_headers: [{"x-nh-key", "nhd_test"}, {"x-nh-signature", "sig"}]}
      })

    {:ok, state} = DeviceSocket.init(state)
    state
  end

  defp extensions(channel), do: :sys.get_state(channel.channel_pid).assigns.extensions
  defp session(channel), do: :sys.get_state(channel.channel_pid).assigns.session

  defp attach_unanswered() do
    test = self()
    id = "unanswered-#{inspect(make_ref())}"

    :telemetry.attach(
      id,
      [:nerves_hub, :device_link, :unanswered],
      fn _event, _measurements, metadata, _config -> send(test, {:unanswered, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  defp assert_unanswered(function, reason) do
    assert_receive {:unanswered, %{function: ^function, reason: ^reason, device_id: 1234}}, 1_000
  end
end
