defmodule NervesHub.Scripts.RunnerTest do
  use ExUnit.Case, async: true

  alias NervesHub.Scripts.Runner

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
end
