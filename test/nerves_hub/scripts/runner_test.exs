defmodule NervesHub.Scripts.RunnerTest do
  use ExUnit.Case, async: false

  alias NervesHub.Scripts.Runner

  @device_id 999_999

  describe "send/3" do
    test "returns {:ok, output} when device channel replies with {:output, result}" do
      device = %{id: @device_id}
      command = %{text: "echo hello"}

      # Subscribe to the device channel topic to act as the "device channel"
      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{@device_id}")

      task =
        Task.async(fn ->
          Runner.send(device, command, 2_000)
        end)

      # Simulate the device channel receiving {:run_script, runner_pid, text}
      assert_receive {:run_script, runner_pid, "echo hello"}, 1_000

      # Reply as the device channel would
      send(runner_pid, {:output, "hello"})

      assert {:ok, "hello"} = Task.await(task, 3_000)
    end

    test "returns {:error, message} when timeout elapses with no reply" do
      device = %{id: @device_id + 1}
      command = %{text: "echo hello"}

      result = Runner.send(device, command, 50)

      assert {:error, message} = result
      assert String.contains?(message, "did not respond")
    end

    test "falls back to console broadcast and subscribes when device replies {:error, :incompatible_version}" do
      device_id = @device_id + 2
      device = %{id: device_id}
      command = %{text: "echo fallback"}

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device_id}")

      task =
        Task.async(fn ->
          Runner.send(device, command, 2_000)
        end)

      assert_receive {:run_script, runner_pid, "echo fallback"}, 1_000

      # Simulate incompatible device version
      send(runner_pid, {:error, :incompatible_version})

      # Give the runner time to subscribe to the console topic
      Process.sleep(50)

      # Broadcast "up" events to the user console group (as the device console channel would)
      NervesHub.Consoles.PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "line1\n"})
      NervesHub.Consoles.PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "line2\n"})
      NervesHub.Consoles.PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "[NERVESHUB:END]\n"})

      # The runner drops only the trailing empty string after the final newline,
      # keeping the [NERVESHUB:END] line itself in the result
      assert {:ok, result} = Task.await(task, 3_000)
      assert String.contains?(result, "line1")
      assert String.contains?(result, "line2")
    end

    test "buffers partial console output until [NERVESHUB:END] marker" do
      device_id = @device_id + 3
      device = %{id: device_id}
      command = %{text: "echo partial"}

      Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device_id}")

      task =
        Task.async(fn ->
          Runner.send(device, command, 2_000)
        end)

      assert_receive {:run_script, runner_pid, "echo partial"}, 1_000

      send(runner_pid, {:error, :incompatible_version})

      Process.sleep(50)

      # Send partial chunks through the user console group
      NervesHub.Consoles.PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "partial out"})
      NervesHub.Consoles.PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "put\n[NERVESHUB:END]\n"})

      assert {:ok, result} = Task.await(task, 3_000)
      assert String.contains?(result, "partial output")
    end
  end

  describe "handle_info" do
    test "unhandled messages are ignored and GenServer stays alive" do
      {:ok, pid} = Runner.start_link(%{id: @device_id + 4})

      send(pid, :some_unhandled_message)
      Process.sleep(10)

      assert Process.alive?(pid)
    end
  end
end
