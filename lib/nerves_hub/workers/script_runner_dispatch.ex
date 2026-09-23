defmodule NervesHub.Workers.ScriptRunnerDispatch do
  @moduledoc """
  Paces one script runner, so concurrent runs share the fleet rather than queue
  behind each other.

  The `script_runners` queue's own limit caps how many scripts a node runs at
  once, but a queue limit knows nothing about which run a job belongs to: with one
  queue, the run that got there first holds every slot until it is done, and a
  ten-device run queued behind a fifty-thousand-device one waits for all fifty
  thousand. This worker is what makes the share per run.

  One of these exists per active run. Each pass works out the run's share —
  the ceiling divided by the number of runs in flight — inserts jobs for that many
  of its devices, and snoozes. So the number of `script_runners` jobs queued at
  any moment is bounded by the ceiling rather than by the size of the run, which
  is what keeps `oban_jobs` small when a run targets a whole fleet.

  Shares are recomputed every pass, so a run starting alongside three others picks
  up its quarter on the next tick without anything being cancelled: devices
  already dispatched are left to finish, since the device is going to answer
  either way and dropping the answer would only lose the output.
  """

  use Oban.Worker,
    queue: :script_runner_dispatch,
    # A pass that fails is worth retrying: unlike the device jobs, nothing has
    # been sent to a device, so retrying only re-reads the queue.
    max_attempts: 5,
    # One dispatcher per run. Without this a retry landing next to a snooze would
    # give a run two pacers, and two pacers means twice the share.
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:script_runner_id],
      fields: [:worker, :args]
    ]

  alias NervesHub.Repo
  alias NervesHub.ScriptRunners
  alias NervesHub.ScriptRunners.ScriptRunner
  alias NervesHub.Workers.ScriptRunnerDevice

  @queue :script_runners

  # Used only if the queue is missing from the config, which would mean nothing
  # could run anyway -- the value just keeps the arithmetic sane rather than
  # dividing by a nil.
  @default_ceiling 500

  # Long enough that a pass is cheap next to the 30s a device script can take,
  # short enough that slots freed by finished devices are refilled promptly.
  @snooze_seconds 5

  @doc """
  How many scripts may be in flight on one node.

  Read from the `#{inspect(@queue)}` queue's own configured limit rather than
  kept alongside it: this decides how many jobs are queued and the limit decides
  how many of them run, so two copies of the number could drift into either
  starving the queue or piling up jobs it cannot start.
  """
  @spec ceiling() :: pos_integer()
  def ceiling() do
    :nerves_hub
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Keyword.get(@queue)
    |> queue_limit()
  end

  # A queue is configured as either a bare limit or a keyword list carrying one.
  defp queue_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp queue_limit(opts) when is_list(opts), do: Keyword.get(opts, :limit, @default_ceiling)
  defp queue_limit(_missing), do: @default_ceiling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"script_runner_id" => runner_id}}) do
    Logger.metadata(script_runner_id: runner_id)

    case Repo.get(ScriptRunner, runner_id) do
      nil -> {:cancel, "script runner #{runner_id} no longer exists"}
      %ScriptRunner{status: :completed} -> :ok
      runner -> dispatch(runner)
    end
  end

  defp dispatch(runner) do
    # A device left at `:running` by a node that died would otherwise hold its
    # place forever, and the run would never finish.
    _ = ScriptRunners.release_stale_devices(runner.id)

    case ScriptRunners.unfinished_device_count(runner.id) do
      0 -> finish(runner)
      _unfinished -> dispatch_share(runner)
    end
  end

  defp dispatch_share(runner) do
    runner = ensure_running(runner)

    share = max(1, div(ceiling(), ScriptRunners.active_run_count()))

    # Only the devices this run has out count against its share. Devices being
    # worked on by another node count too, since the share is about the run rather
    # than about this node -- the per-node ceiling is the queue's own business.
    in_flight = ScriptRunners.unfinished_device_count(runner.id) - ScriptRunners.pending_device_count(runner.id)

    runner.id
    |> ScriptRunners.claim_pending_devices(share - in_flight)
    |> insert_device_jobs(runner)

    {:snooze, @snooze_seconds}
  end

  defp insert_device_jobs([], _runner), do: :ok

  defp insert_device_jobs(device_ids, runner) do
    jobs =
      Enum.map(device_ids, fn device_id ->
        ScriptRunnerDevice.new(%{
          script_runner_id: runner.id,
          device_id: device_id,
          # Carried on the job rather than read back per device: the text is
          # immutable, so a job always runs what the run recorded.
          text: runner.text
        })
      end)

    _ = Oban.insert_all(jobs)

    :ok
  end

  defp ensure_running(%ScriptRunner{status: :pending} = runner) do
    {:ok, runner} = ScriptRunners.mark_running(runner)
    :ok = ScriptRunners.broadcast_progress(runner.id, :started)

    runner
  end

  defp ensure_running(runner), do: runner

  defp finish(runner) do
    {:ok, _runner} = ScriptRunners.mark_finished(runner)

    :ok = ScriptRunners.broadcast_progress(runner.id, :finished)

    :ok
  end
end
