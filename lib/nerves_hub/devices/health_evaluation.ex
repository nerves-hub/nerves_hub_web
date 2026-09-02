defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Judges a device's health against its product's profile, as each metric
  report arrives — on the `metrics` extension or the `health` extension,
  both of which store through `NervesHub.Devices.Metrics.record/3` and
  judge through here: fetch the profile's windows of readings from the
  metric history in ClickHouse, count them with the pure core in
  `NervesHub.Devices.HealthEvaluation.Windows`, merge the built-in
  judgements ("disconnects" counts connectivity events), summarize. One
  windowed read per report, run in the channel process; ClickHouse is
  built for exactly this shape, so there is no cache, no process, and no
  state anywhere.

  The report's own readings are taken in hand rather than read back:
  `record/3` buffers its ClickHouse write, so the freshest samples are the
  ones the store cannot serve yet. Batched readings carry device
  timestamps, and `Windows` buckets them where they belong, so a device
  reporting late lands its catch-up data in the right minutes.

  Without ClickHouse there is no history to window, so evaluation falls
  back to the legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus` — as does a device whose product has no
  profile (backfill not run).
  """

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthEvaluation.Windows
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Helpers.Logging
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfiles

  require Logger

  @type status() :: :unknown | :healthy | :warning | :unhealthy
  @type reasons() :: %{warning: map(), unhealthy: map()} | nil

  @typedoc "A reading in hand: not yet readable from the store."
  @type sample() :: {key :: String.t(), DateTime.t(), value :: number()}

  @doc """
  Health status and reasons for the device described by `device_info` (a
  `NervesHub.DeviceLink.DeviceInfo`), judging the stored history plus the
  `in_hand_samples` that just arrived and are still in the write buffer.
  """
  @spec evaluate(struct() | map(), [sample()]) :: {status(), reasons()}
  def evaluate(device_info, in_hand_samples) do
    with true <- Application.get_env(:nerves_hub, :analytics_enabled, false),
         %HealthProfile{} = profile <- HealthProfiles.resolve(device_info.product_id, platform(device_info)) do
      minute = Windows.minute(DateTime.utc_now())
      samples = stored_samples(device_info, profile) ++ in_hand_samples

      profile
      |> Windows.from_samples(samples, minute)
      |> Windows.judge(profile, minute)
      |> Enum.concat(built_in_judgements(profile, device_info))
      |> Windows.summarize()
    else
      _no_clickhouse_or_no_profile -> legacy(in_hand_samples)
    end
  end

  @doc """
  Evaluate, then persist the verdict as a `device_health` row and broadcast
  it. `report_data` is the payload stored on the row — the health
  extension's full report; `nil` carries the previous row's data forward,
  so alarms and metadata stay displayed when the readings arrived without
  them (the metrics extension).
  """
  @spec evaluate_and_save(struct() | map(), [sample()], map() | nil) :: :ok | :error
  def evaluate_and_save(device_info, in_hand_samples, report_data \\ nil) do
    {status, reasons} = evaluate(device_info, in_hand_samples)

    device_health = %{
      "device_id" => device_info.device_id,
      "data" => report_data || Health.latest_report_data(device_info.device_id),
      "status" => status,
      "status_reasons" => reasons
    }

    case Health.save_device_health(device_health) do
      {:ok, _health} ->
        :ok = ExtensionsPubSub.broadcast_report(device_info.device_id, "health_check_report", %{})

      {:error, error} ->
        Logger.warning("Failed to save health check data: #{inspect(error)}")
        Logging.log_to_sentry(device_info, "[HealthEvaluation] Failed to save health check data.")
        :error
    end
  end

  # One windowed read over the profile's longest period covers every
  # metric's windows.
  defp stored_samples(device_info, %HealthProfile{} = profile) do
    regular = Enum.reject(profile.metrics, & &1.built_in)
    keys = Enum.map(regular, & &1.key)

    longest =
      regular
      |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
      |> Enum.max(fn -> 0 end)

    Metrics.samples_since(device_info.device_id, keys, longest)
  end

  # Built-ins move independently of what the device reports — each has its
  # own query.
  defp built_in_judgements(%HealthProfile{} = profile, device_info) do
    for metric <- profile.metrics, metric.built_in do
      judge_built_in(metric, device_info)
    end
  end

  defp judge_built_in(%{key: "disconnects"} = metric, device_info) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      {warning_count, alert_count} =
        Connections.disconnection_counts(
          device_info.org_id,
          device_info.product_id,
          device_info.device_id,
          {metric.warning_period_seconds, metric.alert_period_seconds}
        )

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

  # A built-in this release doesn't know how to evaluate: rows written by a
  # newer node during a rolling deploy. No opinion beats a wrong one.
  defp judge_built_in(_metric, _device_info), do: :unknown

  defp count_reason(count, threshold, period_seconds) do
    %{value: count, threshold: threshold, period_seconds: period_seconds, aggregation: :count}
  end

  # The latest in-hand value per key, judged instantaneously — all the
  # legacy check ever looked at.
  defp legacy(in_hand_samples) do
    metrics =
      in_hand_samples
      |> Enum.sort_by(fn {_key, timestamp, _value} -> timestamp end, DateTime)
      |> Map.new(fn {key, _timestamp, value} -> {key, value} end)

    case HealthStatus.calculate_metrics_status(metrics) do
      {status, reasons} -> {status, reasons}
      status -> {status, nil}
    end
  end

  defp platform(%{firmware_metadata: %{platform: platform}}), do: platform
  defp platform(%{firmware_metadata: %{"platform" => platform}}), do: platform
  defp platform(_device_info), do: nil
end
