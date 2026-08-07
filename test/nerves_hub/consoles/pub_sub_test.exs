defmodule NervesHub.Consoles.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Consoles.PubSub
  alias NervesHub.Extensions.LocalShell
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  describe "console liveness registry" do
    test "console_active? is false with no console channel joined", %{device_id: device_id} do
      refute PubSub.console_active?(device_id)
    end

    test "console_active? is true once the console channel has joined", %{device_id: device_id} do
      :ok = PubSub.join_console(device_id)
      assert PubSub.console_active?(device_id)
    end

    test "console_active? returns to false when the console channel process dies", %{
      device_id: device_id
    } do
      parent = self()

      pid =
        spawn(fn ->
          :ok = PubSub.join_console(device_id)
          send(parent, :joined)
          receive(do: (:stop -> :ok))
        end)

      assert_receive :joined, 500
      assert PubSub.console_active?(device_id)

      ref = Process.monitor(pid)
      send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      # Membership is cleaned up asynchronously when the process dies.
      assert eventually(fn -> not PubSub.console_active?(device_id) end)
    end
  end

  describe "console connect handshake" do
    test "connect_to_console reaches the joined console channel", %{device_id: device_id} do
      :ok = PubSub.join_console(device_id)

      :ok = PubSub.connect_to_console(device_id, self())

      assert_receive {:connect, pid}, 500
      assert pid == self()
    end
  end

  describe "console byte streams" do
    test "broadcast_to_console delivers a %Broadcast{} to the device-side group", %{
      device_id: device_id
    } do
      :ok = PubSub.join_console(device_id)

      :ok = PubSub.broadcast_to_console(device_id, "dn", %{"data" => "ls\r"})

      topic = "device:console:#{device_id}"
      assert_receive %Broadcast{topic: ^topic, event: "dn", payload: %{"data" => "ls\r"}}, 500
    end

    test "the console watcher receives file-data transfer events", %{device_id: device_id} do
      # The device Show LiveView watches the console for file-transfer progress.
      :ok = PubSub.subscribe_console_watcher(device_id)

      :ok = PubSub.broadcast_to_console(device_id, "file-data/start", %{"size" => 10})
      :ok = PubSub.broadcast_to_console(device_id, "file-data", %{"chunk" => "abc"})
      :ok = PubSub.broadcast_to_console(device_id, "file-data/stop", %{})

      assert_receive %Broadcast{event: "file-data/start", payload: %{"size" => 10}}, 500
      assert_receive %Broadcast{event: "file-data", payload: %{"chunk" => "abc"}}, 500
      assert_receive %Broadcast{event: "file-data/stop"}, 500
    end

    test "broadcast_to_user_console delivers device output to a user subscriber", %{
      device_id: device_id
    } do
      :ok = PubSub.subscribe_user_console(device_id)

      :ok = PubSub.broadcast_to_user_console(device_id, "up", %{data: "hello"})

      topic = "user:console:#{device_id}"
      assert_receive %Broadcast{topic: ^topic, event: "up", payload: %{data: "hello"}}, 500
    end

    test "broadcast_console_joined reaches the console watcher", %{device_id: device_id} do
      :ok = PubSub.subscribe_console_watcher(device_id)

      :ok = PubSub.broadcast_console_joined(device_id)

      assert_receive %Broadcast{event: "console_joined"}, 500
    end

    test "a user subscriber does not receive the device-side console stream", %{
      device_id: device_id
    } do
      :ok = PubSub.subscribe_user_console(device_id)

      :ok = PubSub.broadcast_to_console(device_id, "dn", %{"data" => "x"})

      refute_receive %Broadcast{event: "dn"}, 200
    end
  end

  describe "local shell" do
    test "local_shell_active? tracks attach/detach", %{device_id: device_id} do
      refute PubSub.local_shell_active?(device_id)

      :ok = PubSub.join_local_shell(device_id)
      assert PubSub.local_shell_active?(device_id)

      :ok = PubSub.leave_local_shell(device_id)
      assert eventually(fn -> not PubSub.local_shell_active?(device_id) end)
    end

    test "monitor_local_shell delivers join and leave events to the caller", %{
      device_id: device_id
    } do
      :ok = PubSub.monitor_local_shell(device_id)

      :ok = PubSub.join_local_shell(device_id)
      assert_receive {:group, [%Group.Event{type: :joined, key: key}], _}, 500
      assert key == "local_shell/#{device_id}"

      :ok = PubSub.leave_local_shell(device_id)
      assert_receive {:group, [%Group.Event{type: :left, key: ^key}], _}, 500
    end

    test "connect_to_local_shell routes a LocalShell-tagged connect", %{device_id: device_id} do
      :ok = PubSub.join_local_shell(device_id)

      :ok = PubSub.connect_to_local_shell(device_id, self())

      assert_receive {LocalShell, {:connect, pid}}, 500
      assert pid == self()
    end

    test "broadcast_to_local_shell delivers input to the device-side group", %{
      device_id: device_id
    } do
      :ok = PubSub.join_local_shell(device_id)

      :ok = PubSub.broadcast_to_local_shell(device_id, "local_shell:shell_input", %{"data" => "x"})

      assert_receive %Broadcast{event: "local_shell:shell_input", payload: %{"data" => "x"}}, 500
    end

    test "broadcast_to_user_local_shell delivers output to a user subscriber", %{
      device_id: device_id
    } do
      :ok = PubSub.subscribe_user_local_shell(device_id)

      :ok = PubSub.broadcast_to_user_local_shell(device_id, "output", %{data: "hi"})

      topic = "user:local_shell:#{device_id}"
      assert_receive %Broadcast{topic: ^topic, event: "output", payload: %{data: "hi"}}, 500
    end
  end

  # Group membership updates from process death / leave are asynchronous.
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts <= 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end
end
