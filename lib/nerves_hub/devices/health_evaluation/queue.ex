defmodule NervesHub.Devices.HealthEvaluation.Queue do
  @moduledoc """
  Health evaluations waiting to run, one queue per node.

  A device's health and metrics reports used to judge its health in the call
  that delivered them. That call is what the process holding the device's
  connection waits on, and judging runs ClickHouse queries. When a whole fleet
  reconnected at once and ClickHouse slowed down, reports outlived the caller's
  timeout, the connection's extensions crashed, and the device rejoined and was
  asked for another report, which kept the overload going on its own. So a
  report now queues its evaluation here and returns.

  ## Newest report wins, and no reading is lost

  The queue is keyed by device. A report for a device that already has one
  waiting replaces it: the newer `DeviceInfo` is the one judged, at the older
  one's place in line, so a device does not lose its turn by reporting again.
  A health report and a metrics report from the same device become one
  evaluation, not two.

  The readings are merged rather than replaced. `Metrics.record/3` buffers its
  ClickHouse write, so the older report's readings may not be readable yet, and
  replacing them would leave them out of the verdict. Merged, each reading
  counts once whether or not it has been flushed, because the stored count
  leaves out the readings held in hand; see
  `NervesHub.Devices.Metrics.health_breach_counts/4`.

  ## Bounded

    * At most `:concurrency` evaluations run at once. Each holds one analytics
      connection at a time, so this stays below the analytics pool, leaving
      the rest for the web UI and everything else. Unset, it is half the pool,
      and at most 10.
    * One evaluation per device at a time, so an older verdict can never be
      saved after a newer one. A report that arrives while its device is being
      judged waits for that to finish.
    * An evaluation that has waited longer than `:max_age` (a minute by
      default) is dropped. Its readings are stored all the same, and the
      device's next report judges them. Each drop emits
      `[:nerves_hub, :health_evaluation, :dropped]`, and a summary is logged at
      most every ten seconds. Nothing goes to Sentry for a drop.

  ## Failures

  An evaluation that raises is counted, and the first one in each ten seconds
  is sent to Sentry. The rest are only counted and logged in the summary: when
  ClickHouse is overloaded every evaluation fails the same way, and one event
  says so as well as thousands.

  Every finished evaluation emits `[:nerves_hub, :health_evaluation,
  :evaluated]`, with how long it waited and how long it ran.

  Nothing here survives a restart. Pending evaluations are lost when the node
  stops, and the device's next report evaluates again.
  """

  use GenServer

  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Helpers.Logging

  require Logger

  @max_concurrency 10
  @default_max_age to_timeout(minute: 1)
  @summary_interval to_timeout(second: 10)

  # A metrics message carries at most 60 reports of at most 20 kept readings.
  # A device reporting again and again before its evaluation runs keeps the
  # newest of these.
  @max_samples 1_200

  defmodule Entry do
    @moduledoc false
    defstruct [:callers, :device_info, :enqueued_at, :samples]
  end

  defmodule State do
    @moduledoc false
    defstruct [
      :concurrency,
      :evaluator,
      :max_age,
      :reported_at,
      :reporter,
      :summary_interval,
      :summary_timer,
      :task_supervisor,
      busy: MapSet.new(),
      drainers: [],
      dropped: 0,
      failed: 0,
      order: :queue.new(),
      pending: %{},
      running: %{}
    ]
  end

  @doc """
  Starts the queue.

  ## Options

    * `:name` - the registered name, defaults to this module.
    * `:concurrency` - how many evaluations may run at once.
    * `:max_age` - how long, in milliseconds, an evaluation may wait to start.
    * `:evaluator` - the function an entry is handed to, defaults to
      `HealthEvaluation.evaluate_and_save/2`.
    * `:task_supervisor` - where evaluations run, defaults to
      `NervesHub.TaskSupervisor`.
    * `:reporter` - how a failure is reported, defaults to
      `NervesHub.Helpers.Logging.log_to_sentry/3`.
    * `:summary_interval` - how often, in milliseconds, drops and failures are
      summarised, and at most how often a failure is reported.

  Options not given are read from `config :nerves_hub, #{inspect(__MODULE__)}`.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Queues a health evaluation of the device described by `device_info`, with the
  readings that report brought.

  Returns at once: this is what a device's report calls, and the report must not
  wait on the evaluation.
  """
  @spec enqueue(GenServer.server(), struct() | map(), [HealthEvaluation.sample()]) :: :ok
  def enqueue(server \\ __MODULE__, device_info, samples) do
    # Who asked, so an evaluation is run on behalf of the process that queued
    # it. Nothing in production reads this; the Ecto sandbox does, which is
    # how an evaluation queued from a test reaches that test's connection.
    callers = [self() | Process.get(:"$callers", [])]

    GenServer.cast(server, {:enqueue, device_info, samples, callers})
  end

  @doc """
  Waits until nothing is waiting or running. For tests that read back what an
  evaluation saved.

  ## Options

    * `:server` - the queue, defaults to this module.
    * `:device_id` - wait only for this device's evaluations.
    * `:timeout` - defaults to five seconds.
  """
  @spec drain(keyword()) :: :ok
  def drain(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    device_id = Keyword.get(opts, :device_id, :all)

    GenServer.call(server, {:drain, device_id}, Keyword.get(opts, :timeout, to_timeout(second: 5)))
  end

  @impl GenServer
  def init(opts) do
    config = Keyword.merge(Application.get_env(:nerves_hub, __MODULE__, []), opts)

    state = %State{
      concurrency: Keyword.get(config, :concurrency) || default_concurrency(),
      evaluator: Keyword.get(config, :evaluator, &HealthEvaluation.evaluate_and_save/2),
      max_age: System.convert_time_unit(Keyword.get(config, :max_age, @default_max_age), :millisecond, :native),
      task_supervisor: Keyword.get(config, :task_supervisor, NervesHub.TaskSupervisor),
      reporter: Keyword.get(config, :reporter, &Logging.log_to_sentry/3),
      summary_interval: Keyword.get(config, :summary_interval, @summary_interval)
    }

    :ok = warn_if_pool_too_small(state.concurrency)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:enqueue, device_info, samples, callers}, state) do
    device_id = device_info.device_id

    state =
      case state.pending do
        %{^device_id => %Entry{} = entry} ->
          entry = %{
            entry
            | device_info: device_info,
              samples: merge_samples(entry.samples, samples),
              callers: callers
          }

          %{state | pending: Map.put(state.pending, device_id, entry)}

        %{} ->
          entry = %Entry{
            device_info: device_info,
            samples: merge_samples([], samples),
            enqueued_at: System.monotonic_time(),
            callers: callers
          }

          state = %{state | pending: Map.put(state.pending, device_id, entry)}

          # A device being judged right now joins the line when that finishes.
          if MapSet.member?(state.busy, device_id), do: state, else: %{state | order: :queue.in(device_id, state.order)}
      end

    {:noreply, dispatch(state)}
  end

  @impl GenServer
  def handle_call({:drain, device_id}, from, state) do
    if idle?(state, device_id) do
      {:reply, :ok, state}
    else
      {:noreply, %{state | drainers: [{from, device_id} | state.drainers]}}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, %State{running: running} = state) when is_map_key(running, ref) do
    Process.demonitor(ref, [:flush])

    {:noreply, finish(state, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{running: running} = state)
      when is_map_key(running, ref) do
    {:noreply, finish(state, ref, {:error, {:exit, reason}, []})}
  end

  def handle_info(:summarize, state) do
    if state.dropped > 0 or state.failed > 0 do
      Logger.warning(
        "[HealthEvaluation.Queue] in the last #{div(state.summary_interval, 1000)}s: " <>
          "#{state.dropped} dropped after waiting over #{max_age_seconds(state)}s, #{state.failed} failed"
      )
    end

    {:noreply, %{state | dropped: 0, failed: 0, summary_timer: nil}}
  end

  def handle_info(_unexpected, state), do: {:noreply, state}

  # Start evaluations, oldest first, while there is room. The line is in the
  # order evaluations were first queued, so once its head is young enough to
  # run, so is everything behind it.
  defp dispatch(%State{} = state) do
    with true <- map_size(state.running) < state.concurrency,
         {{:value, device_id}, order} <- :queue.out(state.order) do
      {entry, pending} = Map.pop!(state.pending, device_id)
      state = %{state | order: order, pending: pending}
      waited = System.monotonic_time() - entry.enqueued_at

      if waited > state.max_age do
        state
        |> drop(entry, waited)
        |> notify_drainers()
        |> dispatch()
      else
        state
        |> start(entry, waited)
        |> dispatch()
      end
    else
      _full_or_empty -> state
    end
  end

  defp start(state, entry, waited) do
    evaluator = state.evaluator

    task = Task.Supervisor.async_nolink(state.task_supervisor, fn -> evaluate(evaluator, entry) end)

    %{
      state
      | running: Map.put(state.running, task.ref, {entry.device_info, waited, System.monotonic_time()}),
        busy: MapSet.put(state.busy, entry.device_info.device_id)
    }
  end

  # Runs in the task.
  defp evaluate(evaluator, entry) do
    Process.put(:"$callers", entry.callers)

    case evaluator.(entry.device_info, entry.samples) do
      :ok -> :ok
      # `evaluate_and_save/2` failing to save has already logged and reported it.
      :error -> :error
    end
  rescue
    exception -> {:error, exception, __STACKTRACE__}
  catch
    kind, reason -> {:error, {kind, reason}, __STACKTRACE__}
  end

  defp finish(state, ref, result) do
    {{device_info, waited, started_at}, running} = Map.pop!(state.running, ref)
    device_id = device_info.device_id

    :telemetry.execute(
      [:nerves_hub, :health_evaluation, :evaluated],
      %{wait_time: waited, duration: System.monotonic_time() - started_at},
      %{device_id: device_id, result: if(result == :ok, do: :ok, else: :failed)}
    )

    state = %{state | running: running, busy: MapSet.delete(state.busy, device_id)}

    # A report that arrived while this device was being judged.
    state =
      if Map.has_key?(state.pending, device_id),
        do: %{state | order: :queue.in(device_id, state.order)},
        else: state

    state
    |> record_failure(device_info, result)
    |> dispatch()
    |> notify_drainers()
  end

  defp record_failure(state, _device_info, :ok), do: state
  defp record_failure(state, _device_info, :error), do: count(state, :failed)

  defp record_failure(state, device_info, {:error, error, stacktrace}) do
    state = count(state, :failed)
    now = System.monotonic_time(:millisecond)

    if is_nil(state.reported_at) or now - state.reported_at >= state.summary_interval do
      report(state, device_info, error, stacktrace)
      %{state | reported_at: now}
    else
      state
    end
  end

  # In a task of its own: Sentry's tags are set on the calling process, and
  # this one is not about any one device.
  defp report(state, device_info, error, stacktrace) do
    error =
      case error do
        exception when is_exception(exception) -> exception
        {kind, reason} -> "[HealthEvaluation.Queue] evaluation #{kind}: #{inspect(reason)}"
      end

    extra = %{stacktrace: Exception.format_stacktrace(stacktrace)}

    reporter = state.reporter

    _ = Task.Supervisor.start_child(state.task_supervisor, fn -> reporter.(device_info, error, extra) end)

    :ok
  end

  defp drop(state, entry, waited) do
    :telemetry.execute([:nerves_hub, :health_evaluation, :dropped], %{count: 1, wait_time: waited}, %{
      device_id: entry.device_info.device_id
    })

    count(state, :dropped)
  end

  defp count(state, field) do
    state = Map.update!(state, field, &(&1 + 1))

    if state.summary_timer do
      state
    else
      %{state | summary_timer: Process.send_after(self(), :summarize, state.summary_interval)}
    end
  end

  defp notify_drainers(%State{drainers: []} = state), do: state

  defp notify_drainers(state) do
    {done, waiting} = Enum.split_with(state.drainers, fn {_from, device_id} -> idle?(state, device_id) end)

    Enum.each(done, fn {from, _device_id} -> GenServer.reply(from, :ok) end)

    %{state | drainers: waiting}
  end

  defp idle?(state, :all), do: state.pending == %{} and state.running == %{}

  defp idle?(state, device_id),
    do: not Map.has_key?(state.pending, device_id) and not MapSet.member?(state.busy, device_id)

  # Deduplicated on key and timestamp, which is what a reading is: the same
  # report delivered twice adds nothing. The newest readings are kept.
  defp merge_samples(older, newer) do
    (newer ++ older)
    |> Enum.uniq_by(fn {key, timestamp, _value} -> {key, timestamp} end)
    |> Enum.sort_by(fn {_key, timestamp, _value} -> timestamp end, {:desc, DateTime})
    |> Enum.take(@max_samples)
  end

  defp max_age_seconds(state), do: System.convert_time_unit(state.max_age, :native, :second)

  defp analytics_pool() do
    config = Application.get_env(:nerves_hub, NervesHub.AnalyticsRepo, [])

    # Ecto's own default pool size, and DBConnection's default pool count.
    Keyword.get(config, :pool_size, 10) * Keyword.get(config, :pool_count, 1)
  end

  defp default_concurrency(), do: analytics_pool() |> div(2) |> max(1) |> min(@max_concurrency)

  defp warn_if_pool_too_small(concurrency) do
    pool = analytics_pool()

    if Application.get_env(:nerves_hub, :analytics_enabled) && concurrency >= pool do
      Logger.warning(
        "[HealthEvaluation.Queue] concurrency #{concurrency} is not below the analytics pool of #{pool}: " <>
          "health evaluations can take every analytics connection"
      )
    end

    :ok
  end
end
