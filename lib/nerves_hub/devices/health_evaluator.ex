defmodule NervesHub.Devices.HealthEvaluator do
  @moduledoc """
  Per-product health evaluation with in-memory sliding windows: reports are
  judged without touching the database, and status changes driven purely by
  time — samples aging out of their windows — happen on a minute tick
  instead of never.

  One evaluator runs per product *per node*, started on demand and looked up
  through a local `Registry`. That is safe without cluster-wide coordination
  because a device's reports all arrive over its one connection, so one
  node's evaluator sees that device's full stream. Tracking follows the
  connection: the device socket's terminate tells the evaluator to forget
  the device (covering abrupt disconnects — power loss, crashed channels —
  that the extension's own detach message never announces), and the tick
  drops any entry silent for longer than the profile's longest window as a
  backstop for terminates that never ran. A dropped or disconnected device
  keeps its last written status — deliberately: offline is what the
  connection status is for, and a health opinion from when it last reported
  stays true of that moment. Wherever it reconnects warms it up again from
  the stored metrics.

  The GenServer itself never queries. Everything that reads a database runs
  in the calling channel process, where it parallelizes across devices and
  is throttled by the pool instead of one mailbox:

    * `judge_report/2` (the client-side orchestrator) fetches the cached
      profile, judges built-in metrics (ClickHouse) caller-side, and for a
      device the evaluator doesn't know yet, rebuilds the windows from
      storage caller-side and hands them over to adopt. A reconnect storm
      costs N parallel pool-limited queries, not a serialized queue.
    * the tick is pure pruning and re-judging; a database write only when a
      device's status actually changed.

  Status semantics are the counting form of the median test: a level
  engages when at least half of the window's samples breach the threshold
  in the metric's unhealthy direction. Profile edits are broadcast by
  `NervesHub.Products.HealthProfiles`; the evaluator debounces the burst a
  page of per-metric Save buttons produces, reloads once, and only drops
  its windows when something evaluation-relevant actually changed — a
  featured-only edit keeps every counter.

  If the evaluator cannot be reached, callers fall back to
  `NervesHub.Devices.HealthEvaluation`, which judges the same way from the
  stored samples.
  """

  use GenServer, restart: :temporary

  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.HealthEvaluator.Windows
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Products.HealthProfiles

  require Logger

  @tick_ms to_timeout(minute: 1)
  @reload_debounce_ms to_timeout(second: 2)
  @call_timeout_ms to_timeout(second: 1)

  # ---------------------------------------------------------------- client

  @doc """
  Judge a report for the device. Runs in the calling process: the cached
  profile comes from the evaluator, but built-in judgements (ClickHouse)
  and, for a device the evaluator doesn't track yet, the window rebuild
  from stored samples (Postgres) all execute here. The report's metrics
  must already be saved — a rebuild must include them.

  `{:error, :unavailable}` when the evaluator cannot be reached or the
  product has no profile — the caller falls back to the query-based
  evaluation (or the legacy check).
  """
  @spec judge_report(struct() | map(), map()) ::
          {:ok, :unknown | :healthy | :warning | :unhealthy, map() | nil} | {:error, :unavailable}
  def judge_report(device_info, report_metrics) do
    with {:ok, pid} <- start_or_lookup(device_info.product_id),
         {:ok, profile} <- call(pid, {:profile, device_info}) do
      built_ins = HealthEvaluation.built_in_judgements(profile, device_info)

      case call(pid, {:report, device_info, report_metrics, built_ins}) do
        {:error, :cold} ->
          minute = Windows.minute(DateTime.utc_now())
          windows = HealthEvaluation.windows_from_storage(device_info, profile, minute)

          call(pid, {:adopt, device_info, windows, built_ins})

        reply ->
          reply
      end
    end
  end

  @doc "The device's connection closed; stop tracking (and ticking for) it."
  @spec forget(pos_integer(), pos_integer()) :: :ok
  def forget(product_id, device_id) do
    case Registry.lookup(__MODULE__.Registry, product_id) do
      [{pid, _}] -> GenServer.cast(pid, {:forget, device_id})
      [] -> :ok
    end
  end

  def start_link(product_id) do
    GenServer.start_link(__MODULE__, product_id, name: {:via, Registry, {__MODULE__.Registry, product_id}})
  end

  defp call(pid, message) do
    GenServer.call(pid, message, @call_timeout_ms)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp start_or_lookup(product_id) do
    case Registry.lookup(__MODULE__.Registry, product_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(__MODULE__.Supervisor, {__MODULE__, product_id}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} -> {:error, :unavailable}
        end
    end
  end

  # ---------------------------------------------------------------- server

  @impl GenServer
  def init(product_id) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, HealthProfiles.topic(product_id))
    _ = Process.send_after(self(), :tick, @tick_ms)

    {:ok,
     %{
       product_id: product_id,
       profiles: HealthProfiles.profiles_by_platform(product_id),
       devices: %{},
       reload_pending?: false
     }}
  end

  @impl GenServer
  def handle_call({:profile, device_info}, _from, state) do
    case profile_for(state, device_info) do
      nil -> {:reply, {:error, :unavailable}, state}
      profile -> {:reply, {:ok, profile}, state}
    end
  end

  def handle_call({:report, device_info, report_metrics, built_ins}, _from, state) do
    minute = Windows.minute(DateTime.utc_now())

    with profile when not is_nil(profile) <- profile_for(state, device_info),
         %{} = device <- state.devices[device_info.device_id] do
      windows = Windows.record(device.windows, profile, report_metrics, minute)

      judge_and_store(state, device_info, device, profile, windows, built_ins, minute)
    else
      nil ->
        reply = if profile_for(state, device_info), do: {:error, :cold}, else: {:error, :unavailable}

        {:reply, reply, state}
    end
  end

  def handle_call({:adopt, device_info, windows, built_ins}, _from, state) do
    minute = Windows.minute(DateTime.utc_now())

    case profile_for(state, device_info) do
      nil ->
        {:reply, {:error, :unavailable}, state}

      profile ->
        # The adopted windows were rebuilt from storage by the caller and
        # already contain the report that triggered this; nothing to record.
        # Last write wins if two rebuilds race — both came from the same
        # storage, and a device's reports serialize on its one connection.
        device = %{
          windows: Windows.new(),
          status: nil,
          reasons: nil,
          built_ins: [],
          platform: platform(device_info),
          last_report_minute: minute
        }

        judge_and_store(state, device_info, device, profile, windows, built_ins, minute)
    end
  end

  defp judge_and_store(state, device_info, device, profile, windows, built_ins, minute) do
    {status, reasons} =
      windows
      |> Windows.judge(profile, minute)
      |> Enum.concat(built_ins)
      |> Windows.summarize()

    device = %{
      device
      | windows: windows,
        status: status,
        reasons: reasons,
        built_ins: built_ins,
        last_report_minute: minute
    }

    {:reply, {:ok, status, reasons}, put_in(state.devices[device_info.device_id], device)}
  end

  @impl GenServer
  def handle_cast({:forget, device_id}, state) do
    {:noreply, %{state | devices: Map.delete(state.devices, device_id)}}
  end

  @impl GenServer
  def handle_info(:tick, %{devices: devices, reload_pending?: false} = state) when devices == %{} do
    # Nothing to track and nothing scheduled to change: stop rather than
    # tick forever for a product with no connected devices on this node.
    {:stop, :normal, state}
  end

  def handle_info(:tick, state) do
    _ = Process.send_after(self(), :tick, @tick_ms)

    {:noreply, run_tick(state, DateTime.utc_now())}
  end

  # Test hook: a tick at a chosen time, without rescheduling. Time-driven
  # expiry otherwise needs a real minute to pass.
  def handle_info({:tick_at, %DateTime{} = now}, state) do
    {:noreply, run_tick(state, now)}
  end

  # A page of per-metric Save buttons produces a burst of these; one
  # debounced reload absorbs it (and redundant broadcasts from other nodes).
  def handle_info({:health_profiles_changed, _product_id}, %{reload_pending?: true} = state) do
    {:noreply, state}
  end

  def handle_info({:health_profiles_changed, _product_id}, state) do
    _ = Process.send_after(self(), :apply_profile_reload, @reload_debounce_ms)

    {:noreply, %{state | reload_pending?: true}}
  end

  def handle_info(:apply_profile_reload, state) do
    profiles = HealthProfiles.profiles_by_platform(state.product_id)

    # Counters are made against thresholds and directions, so they only
    # have to go when one of those changed. A display-only edit — toggling
    # featured — keeps every window; devices re-warm lazily otherwise.
    devices =
      if evaluation_fingerprint(profiles) == evaluation_fingerprint(state.profiles) do
        state.devices
      else
        %{}
      end

    {:noreply, %{state | profiles: profiles, devices: devices, reload_pending?: false}}
  end

  # ------------------------------------------------------------- internals

  defp run_tick(state, now) do
    minute = Windows.minute(now)

    devices =
      for {device_id, device} <- state.devices,
          advanced = advance(state, device_id, device, minute),
          advanced != :drop,
          into: %{},
          do: {device_id, advanced}

    %{state | devices: devices}
  end

  defp advance(state, device_id, device, minute) do
    profile = profile_for(state, device)

    cond do
      is_nil(profile) ->
        :drop

      minute - device.last_report_minute > longest_span(profile) ->
        # Silent past every window: the backstop for a socket terminate
        # that never ran (brutal kills). Dropped without a transition
        # write, so a node holding a stale copy of a device that
        # reconnected elsewhere stops writing over the live node.
        :drop

      true ->
        # Built-in judgements are report-driven (their queries run in the
        # caller); on the tick they are carried until their own windows
        # have fully elapsed since the last report, then dropped — an
        # engaged disconnects level shouldn't outlive its window.
        built_ins =
          if minute - device.last_report_minute >= built_in_span(profile) do
            []
          else
            device.built_ins
          end

        windows = Windows.prune(device.windows, profile, minute)

        {status, reasons} =
          windows |> Windows.judge(profile, minute) |> Enum.concat(built_ins) |> Windows.summarize()

        # TODO: no hysteresis — a device oscillating around a threshold can
        # flip status (one row + broadcast) every minute.
        if status != device.status do
          record_transition(device_id, status, reasons)
        end

        %{device | windows: windows, status: status, reasons: reasons, built_ins: built_ins}
    end
  end

  # A time-driven status change has no report to ride on, so the evaluator
  # writes its own health row. The report payload (alarms, metadata shown in
  # the UI) is carried forward from the latest row: nothing new was reported,
  # and a transition must not blank what is displayed.
  defp record_transition(device_id, status, reasons) do
    case Health.save_device_health(%{
           "device_id" => device_id,
           "data" => Health.latest_report_data(device_id),
           "status" => status,
           "status_reasons" => reasons
         }) do
      {:ok, _} -> ExtensionsPubSub.broadcast_report(device_id, "health_check_report", %{})
      {:error, error} -> Logger.warning("[HealthEvaluator] failed to record transition: #{inspect(error)}")
    end
  rescue
    error -> Logger.warning("[HealthEvaluator] failed to record transition: #{inspect(error)}")
  end

  # Everything about the profiles that counters depend on; `featured` and
  # labels deliberately absent.
  defp evaluation_fingerprint(profiles) do
    profiles
    |> Enum.map(fn {platform, profile} ->
      metrics =
        profile.metrics
        |> Enum.map(
          &{&1.key, &1.built_in, &1.operator, &1.warning_threshold, &1.warning_period_seconds, &1.alert_threshold,
           &1.alert_period_seconds}
        )
        |> Enum.sort()

      {platform, metrics}
    end)
    |> Enum.sort()
    |> :erlang.phash2()
  end

  defp longest_span(profile) do
    profile.metrics
    |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
    |> Enum.max(fn -> 0 end)
    |> seconds_to_span()
  end

  defp built_in_span(profile) do
    profile.metrics
    |> Enum.filter(& &1.built_in)
    |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
    |> Enum.max(fn -> 0 end)
    |> seconds_to_span()
  end

  defp seconds_to_span(seconds), do: div(seconds + 59, 60)

  defp profile_for(state, device_info_or_device) do
    platform = platform(device_info_or_device)

    Map.get(state.profiles, platform) || Map.get(state.profiles, nil)
  end

  defp platform(%{firmware_metadata: %{platform: platform}}), do: platform
  defp platform(%{firmware_metadata: %{"platform" => platform}}), do: platform
  defp platform(%{platform: platform}), do: platform
  defp platform(_), do: nil
end
