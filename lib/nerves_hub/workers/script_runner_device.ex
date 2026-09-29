defmodule NervesHub.Workers.ScriptRunnerDevice do
  @moduledoc """
  Runs one script runner's script on one device and records what it said.

  The `script_runners` queue's concurrency limit is the whole concurrency story:
  Oban runs at most that many of these at a time per node, so there is no budget
  to track here. A job spends nearly all its life waiting on a device, which is
  why the limit is set so much higher than the queues around it.

  One device is one job so that a device which never answers, or takes its own
  process down, costs exactly itself. Every outcome — including the ones where
  nothing was sent — is written to the device's row, so the run is a complete
  record either way.
  """

  use Oban.Worker,
    queue: :script_runners,
    # The script either ran or it did not; both are recorded as the device's
    # outcome. Retrying would mean running an operator's script on a device a
    # second time without being asked, which is not a safe thing to do quietly.
    max_attempts: 1

  alias NervesHub.ScriptRunners
  alias NervesHub.Scripts.Runner

  @timeout to_timeout(second: 30)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"script_runner_id" => runner_id, "device_id" => device_id, "text" => text}}) do
    Logger.metadata(script_runner_id: runner_id, device_id: device_id)

    # Checked here rather than when the run was created: a device that dropped off
    # while the queue worked through the devices ahead of it should be recorded as
    # offline, not sent a script nothing will answer.
    case ScriptRunners.connected_device_ids([device_id]) do
      [^device_id] -> run(runner_id, device_id, text)
      [] -> record(runner_id, device_id, :offline, nil)
    end
  end

  defp run(runner_id, device_id, text) do
    # Only `id` is read off the device, and the connection was just checked.
    %{id: device_id}
    |> Runner.send(%{text: text}, timeout: @timeout, console_fallback?: false)
    |> classify()
    |> then(fn {status, output} -> record(runner_id, device_id, status, output) end)
  end

  defp record(runner_id, device_id, status, output) do
    _ = ScriptRunners.record_device_result(runner_id, device_id, status, output)

    :telemetry.execute([:nerves_hub, :script_runners, :device], %{count: 1}, %{status: status})

    :ok = ScriptRunners.broadcast_progress(runner_id, :device_finished, %{device_id: device_id, status: status})

    :ok
  end

  defp classify({:ok, output}), do: {:completed, output}

  # A device whose client is too old to run scripts at all. The single-device path
  # falls back to typing the script into the device's console; a bulk run does not,
  # since that would take over hundreds of consoles at once.
  defp classify({:error, :unsupported}), do: {:unsupported, nil}

  # `Runner.send/3` turns its own call timeout into this message. The message is
  # only how a timeout is recognised, not something worth keeping: it says the
  # device did not respond in so many milliseconds, which is what `:timed_out`
  # already records. Nothing came back from the device, so there is no output.
  defp classify({:error, message}) when is_binary(message) do
    if String.contains?(message, "did not respond") do
      {:timed_out, nil}
    else
      {:failed, message}
    end
  end

  defp classify(other), do: {:failed, inspect(other)}
end
