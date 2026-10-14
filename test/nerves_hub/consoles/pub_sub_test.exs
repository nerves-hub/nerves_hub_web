defmodule NervesHub.Consoles.PubSubTest do
  use ExUnit.Case, async: true

  alias NervesHub.Consoles.PubSub
  alias NervesHub.Extensions.LocalShell
  alias Phoenix.Socket.Broadcast

  # Unique per test so concurrent tests don't share a Group key.
  setup do
    %{device_id: System.unique_integer([:positive])}
  end

  describe "finding the console" do
    test "the device-side console holds no :group membership", %{device_id: device_id} do
      # The point of the console's design: one subscription per connected
      # device, replicated to every node, is what this avoids.
      :ok = PubSub.subscribe_console(device_id)

      refute Enum.any?(Group.local_entries(NervesHub.Group), fn {_type, _cluster, _key, pid, _meta} ->
               pid == self()
             end)
    end

    test "locate_console reaches the subscribed console with a reply-to and ref", %{
      device_id: device_id
    } do
      :ok = PubSub.subscribe_console(device_id)

      ref = PubSub.locate_console(device_id)

      assert_receive {:locate_console, from, ^ref}, 500
      assert from == self()
    end

    test "locate_console reaches nothing when no console is subscribed", %{device_id: device_id} do
      ref = PubSub.locate_console(device_id)

      refute_receive {:locate_console, _from, ^ref}, 100
    end

    test "connect_to_console reaches the subscribed console", %{device_id: device_id} do
      :ok = PubSub.subscribe_console(device_id)

      :ok = PubSub.connect_to_console(device_id, self())

      assert_receive {:connect, pid}, 500
      assert pid == self()
    end
  end

  describe "liveness monitors" do
    # `Group.monitor/2` is backed by a duplicate-key registry, and the library
    # dedupes subscribers by pid before delivering, so a leaked registration is
    # invisible from the outside. Reaching into the registry is the only way to
    # see it -- hence the coupling to `Group`'s key shape here.
    defp monitor_entries(key) do
      NervesHub.Group
      |> Group.registry_name()
      |> Registry.lookup({NervesHub.Group, nil, {:exact, key}})
    end

    test "monitoring the same device repeatedly registers once", %{device_id: device_id} do
      :ok = PubSub.monitor_local_shell(device_id)
      :ok = PubSub.monitor_local_shell(device_id)
      :ok = PubSub.monitor_local_shell(device_id)

      assert [{pid, _}] = monitor_entries("local_shell/#{device_id}")
      assert pid == self()
    end

    test "demonitor_local_shell stops local shell events", %{device_id: device_id} do
      :ok = PubSub.monitor_local_shell(device_id)
      :ok = PubSub.demonitor_local_shell(device_id)

      :ok = PubSub.join_local_shell(device_id)
      refute_receive {:group, _events, _info}, 200
    end

    test "demonitoring something never monitored is a no-op", %{device_id: device_id} do
      assert :ok = PubSub.demonitor_local_shell(device_id)
    end
  end

  describe "console byte streams" do
    test "broadcast_to_console delivers a %Broadcast{} to the subscribed console", %{
      device_id: device_id
    } do
      :ok = PubSub.subscribe_console(device_id)

      :ok = PubSub.broadcast_to_console(device_id, "dn", %{"data" => "ls\r"})

      topic = "device:console:#{device_id}"
      assert_receive %Broadcast{topic: ^topic, event: "dn", payload: %{"data" => "ls\r"}}, 500
    end

    test "send_to_console delivers straight to a known console, subscribed or not", %{
      device_id: device_id
    } do
      :ok = PubSub.send_to_console(device_id, self(), "dn", %{"data" => "x"})

      topic = "device:console:#{device_id}"
      assert_receive %Broadcast{topic: ^topic, event: "dn", payload: %{"data" => "x"}}
    end

    test "send_to_console broadcasts when the console is not known yet", %{device_id: device_id} do
      :ok = PubSub.subscribe_console(device_id)

      :ok = PubSub.send_to_console(device_id, nil, "dn", %{"data" => "x"})

      assert_receive %Broadcast{event: "dn", payload: %{"data" => "x"}}, 500
    end

    test "the console watcher receives what it is sent, and not the console's input", %{
      device_id: device_id
    } do
      # The device Show LiveView flashes upload start and stop for the uploader.
      :ok = PubSub.subscribe_console_watcher(device_id)

      :ok = PubSub.broadcast_to_console_watchers(device_id, "file-data/start", %{"size" => 10})
      :ok = PubSub.broadcast_to_console(device_id, "file-data", %{"chunk" => "abc"})
      :ok = PubSub.broadcast_to_console_watchers(device_id, "file-data/stop", %{})

      assert_receive %Broadcast{event: "file-data/start", payload: %{"size" => 10}}, 500
      assert_receive %Broadcast{event: "file-data/stop"}, 500
      refute_received %Broadcast{event: "file-data"}
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

    test "leaving without attaching is not an error", %{device_id: device_id} do
      # A device drives detach by sending `local_shell:detached`, and
      # `Extensions.Dispatch` forwards it without checking that an `attached`
      # came first, and does not rescue the call. Returning an error here would
      # let a device crash its own extensions channel.
      assert :ok = PubSub.leave_local_shell(device_id)

      :ok = PubSub.join_local_shell(device_id)
      assert :ok = PubSub.leave_local_shell(device_id)
      assert :ok = PubSub.leave_local_shell(device_id)
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
