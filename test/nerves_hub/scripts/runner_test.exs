defmodule NervesHub.Scripts.RunnerTest do
  use ExUnit.Case, async: true

  alias NervesHub.Consoles.PubSub
  alias NervesHub.Scripts.Runner

  @device_id 999_999

  # `Runner.send/3` only reads `device.id` and `command.text`, so there is no
  # need to put either in the database to exercise the runner itself.
  defp device(), do: %{id: System.unique_integer([:positive])}

  defp start_runner(device, timeout) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "device:#{device.id}")

    # `Task.async` stands in for the callers that leaked runners: it exits
    # `:normal` once the call returns, which a linked runner ignores.
    task = Task.async(fn -> Runner.send(device, %{text: "IO.puts(:hi)"}, timeout) end)

    assert_receive {:run_script, runner, "IO.puts(:hi)"}, 1_000

    {task, runner}
  end

  test "stops itself when nothing answers the script" do
    device = device()
    {task, runner} = start_runner(device, 50)
    ref = Process.monitor(runner)

    assert {:error, message} = Task.await(task, 5_000)
    assert message =~ "did not respond"

    # Before the deadline was added the runner outlived its caller for the life
    # of the node, holding a console subscription and buffering device output.
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}, 5_000
  end

  test "returns the device's output and stops" do
    device = device()
    {task, runner} = start_runner(device, to_timeout(second: 5))
    ref = Process.monitor(runner)

    send(runner, {:output, "hello from the device"})

    assert {:ok, "hello from the device"} = Task.await(task, 5_000)
    assert_receive {:DOWN, ^ref, :process, ^runner, :normal}, 1_000
  end

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
      PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "line1\n"})
      PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "line2\n"})
      PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "[NERVESHUB:END]\n"})

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
      PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "partial out"})
      PubSub.broadcast_to_user_console(device_id, "up", %{"data" => "put\n[NERVESHUB:END]\n"})

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
