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
  # Jobs queued by the previous release also carry a `"text"` arg. It is ignored:
  # the run's own `text` is the same immutable value.
  def perform(%Oban.Job{args: %{"script_runner_id" => runner_id, "device_id" => device_id}}) do
    Logger.metadata(script_runner_id: runner_id, device_id: device_id)

    # Read from the run rather than carried on the job (see
    # `NervesHub.Workers.ScriptRunnerDispatch`). The text never changes once a run
    # exists, so this is still exactly what the run recorded.
    case ScriptRunners.script_text(runner_id) do
      nil -> {:cancel, "script runner #{runner_id} no longer exists"}
      text -> run_if_connected(runner_id, device_id, text)
    end
  end

  # Checked here rather than when the run was created: a device that dropped off
  # while the queue worked through the devices ahead of it should be recorded as
  # offline, not sent a script nothing will answer.
  defp run_if_connected(runner_id, device_id, text) do
    case ScriptRunners.connected_device_ids([device_id]) do
      [^device_id] -> run(runner_id, device_id, text)
      [] -> record(runner_id, device_id, :offline, nil)
    end
  end

  # Marked sent first, so if this job ends without recording an outcome the row
  # is `:abandoned` rather than dispatched again -- the script may have run. See
  # `NervesHub.ScriptRunners.release_stale_devices/2`.
  #
  # Nothing to mark means the row has gone with its run, deleted since the text
  # was read, so nothing is sent.
  defp run(runner_id, device_id, text) do
    case ScriptRunners.mark_sent(runner_id, device_id) do
      0 -> {:cancel, "script runner #{runner_id} no longer has device #{device_id}"}
      _marked -> send_script(runner_id, device_id, text)
    end
  end

  defp send_script(runner_id, device_id, text) do
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
  #
  # The last clause over `Runner.send/3`'s three results, deliberately with
  # nothing after it: anything else would mean that contract changed, and a
  # catch-all would quietly record the new shape as a device failure. Failing here
  # instead leaves the row to be marked `:abandoned` (see
  # `NervesHub.ScriptRunners.release_stale_devices/2`) and says which device it
  # was, rather than writing `inspect/1` output into a column an operator reads
  # as their script's own.
  defp classify({:error, message}) when is_binary(message) do
    if String.contains?(message, "did not respond") do
      {:timed_out, nil}
    else
      {:failed, message}
    end
  end
end
