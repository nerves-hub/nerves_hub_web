defmodule NervesHub.Devices.HealthEvaluator do
  @moduledoc """
  Per-product health evaluation with in-memory sliding windows: reports are
  judged without touching the database, and status changes driven purely by
  time — samples aging out of their windows — happen on a minute tick
  instead of never.

  One evaluator runs per product *per node*, started on demand and looked up
  through a local `Registry`. That is safe without cluster-wide coordination
  because a device's reports all arrive over its one connection, so one
  node's evaluator sees that device's full stream; when the connection
  closes, the extension tells the evaluator to forget the device, and
  wherever the device reconnects warms it up again from the stored metrics.

  The counters live in `NervesHub.Devices.HealthEvaluator.Windows`. Costs:

    * a report — pure counter updates, no queries (built-in metrics such as
      disconnect counts still ask ClickHouse, as they did before);
    * the minute tick — pure pruning and re-judging; a database write only
      when a device's status actually changed;
    * first sighting of a device — one indexed query over its stored
      samples to rebuild the windows.

  Status semantics are the counting form of the median test: a level
  engages when at least half of the window's samples are at or over the
  threshold. A profile edit is broadcast by `NervesHub.Products.HealthProfiles`;
  the evaluator reloads and drops its windows, since counters made against
  old thresholds cannot be reinterpreted, and devices warm up again on
  their next report.

  If the evaluator cannot be reached, callers fall back to
  `NervesHub.Devices.HealthEvaluation` — the screened, query-based path.
  """

  use GenServer, restart: :temporary

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthEvaluator.Windows
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Products.HealthProfiles

  require Logger

  @tick_ms to_timeout(minute: 1)

  # ---------------------------------------------------------------- client

  @doc """
  Judge a report for the device, starting the product's evaluator if this
  node doesn't have one yet. The report's metrics must already be saved (a
  cold device warms up from the database, and its windows must include this
  report).

  `{:error, :unavailable}` when the evaluator cannot be reached — the
  caller falls back to the query-based evaluation.
  """
  @spec evaluate_report(struct() | map(), map()) ::
          {:ok, :unknown | :healthy | :warning | :unhealthy, map() | nil} | {:error, :unavailable}
  def evaluate_report(device_info, report_metrics) do
    with {:ok, pid} <- start_or_lookup(device_info.product_id) do
      GenServer.call(pid, {:report, device_info, report_metrics})
    end
  catch
    :exit, _reason -> {:error, :unavailable}
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

    {:ok, %{product_id: product_id, profiles: HealthProfiles.profiles_by_platform(product_id), devices: %{}}}
  end

  @impl GenServer
  def handle_call({:report, device_info, report_metrics}, _from, state) do
    now = DateTime.utc_now()
    minute = Windows.minute(now)

    case profile_for(state, device_info) do
      nil ->
        {:reply, {:error, :unavailable}, state}

      profile ->
        judge_report(state, device_info, report_metrics, profile, minute)
    end
  rescue
    # Warm-up and built-ins read the database and ClickHouse; when either is
    # unreachable the caller has a query-based fallback of its own, and a
    # crash here would take every device of the product down with it.
    error ->
      Logger.warning("[HealthEvaluator] evaluation failed: #{inspect(error)}")

      {:reply, {:error, :unavailable}, state}
  end

  defp judge_report(state, device_info, report_metrics, profile, minute) do
    device = state.devices[device_info.device_id] || warm_up(device_info, profile, minute)

    windows =
      if device.warmed_this_call? do
        device.windows
      else
        Windows.record(device.windows, profile, report_metrics, minute)
      end

    built_ins = judge_built_ins(profile, device_info)

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
        warmed_this_call?: false
    }

    {:reply, {:ok, status, reasons}, put_in(state.devices[device_info.device_id], device)}
  end

  @impl GenServer
  def handle_cast({:forget, device_id}, state) do
    {:noreply, %{state | devices: Map.delete(state.devices, device_id)}}
  end

  @impl GenServer
  def handle_info(:tick, %{devices: devices} = state) when devices == %{} do
    # Nothing to track and nothing scheduled to change: stop rather than
    # tick forever for a product with no connected devices on this node.
    {:stop, :normal, state}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    {:noreply, run_tick(state, DateTime.utc_now())}
  end

  # Test hook: a tick at a chosen time, without rescheduling. Time-driven
  # expiry otherwise needs a real minute to pass.
  def handle_info({:tick_at, %DateTime{} = now}, state) do
    {:noreply, run_tick(state, now)}
  end

  def handle_info({:health_profiles_changed, _product_id}, state) do
    # Counters were made against the old thresholds and cannot be
    # reinterpreted; drop them and let devices warm up on their next report.
    {:noreply, %{state | profiles: HealthProfiles.profiles_by_platform(state.product_id), devices: %{}}}
  end

  # ------------------------------------------------------------- internals

  defp run_tick(state, now) do
    minute = Windows.minute(now)

    devices =
      state.devices
      |> Map.new(fn {device_id, device} -> {device_id, advance(state, device_id, device, minute)} end)

    %{state | devices: devices}
  end

  defp advance(state, device_id, device, minute) do
    with profile when not is_nil(profile) <- profile_for(state, device),
         windows = Windows.prune(device.windows, profile, minute),
         {status, reasons} =
           windows |> Windows.judge(profile, minute) |> Enum.concat(device.built_ins) |> Windows.summarize(),
         false <- status == device.status do
      record_transition(device_id, status, reasons)

      %{device | windows: windows, status: status, reasons: reasons}
    else
      _no_profile_or_no_change -> device
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

  defp warm_up(device_info, profile, minute) do
    keys = for metric <- profile.metrics, !metric.built_in, do: metric.key

    longest =
      profile.metrics
      |> Enum.reject(& &1.built_in)
      |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
      |> Enum.max(fn -> 0 end)

    samples = Metrics.samples_since(device_info.device_id, keys, longest)

    %{
      windows: Windows.from_samples(profile, samples, minute),
      status: nil,
      reasons: nil,
      built_ins: [],
      platform: platform(device_info),
      warmed_this_call?: true
    }
  end

  defp judge_built_ins(profile, device_info) do
    for metric <- profile.metrics, metric.built_in do
      judge_built_in(metric, device_info)
    end
  end

  defp judge_built_in(%{key: "disconnects"} = metric, device_info) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      count = fn seconds ->
        Connections.disconnection_count(device_info.org_id, device_info.product_id, device_info.device_id, seconds)
      end

      alert_count = count.(metric.alert_period_seconds)
      warning_count = count.(metric.warning_period_seconds)

      cond do
        alert_count >= metric.alert_threshold ->
          {:unhealthy, metric.key, count_reason(alert_count, metric.alert_threshold, metric.alert_period_seconds)}

        warning_count >= metric.warning_threshold ->
          {:warning, metric.key, count_reason(warning_count, metric.warning_threshold, metric.warning_period_seconds)}

        true ->
          :healthy
      end
    else
      :unknown
    end
  end

  defp judge_built_in(_unknown_future_built_in, _device_info), do: :unknown

  defp count_reason(count, threshold, period_seconds) do
    %{value: count, threshold: threshold, period_seconds: period_seconds, aggregation: :count}
  end

  defp profile_for(state, device_info_or_device) do
    platform = platform(device_info_or_device)

    Map.get(state.profiles, platform) || Map.get(state.profiles, nil)
  end

  defp platform(%{firmware_metadata: %{platform: platform}}), do: platform
  defp platform(%{firmware_metadata: %{"platform" => platform}}), do: platform
  defp platform(%{platform: platform}), do: platform
  defp platform(_), do: nil
end
