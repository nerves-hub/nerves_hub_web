defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Judges a device's health against its product's profile, as each report
  arrives: fetch the profile's windows of readings from the metric history
  in ClickHouse, count them with the pure core in
  `NervesHub.Devices.HealthEvaluation.Windows`, merge the built-in
  judgements ("disconnects" counts connectivity events), summarize. One
  windowed read per report, run in the channel process; ClickHouse is
  built for exactly this shape, so there is no cache, no process, and no
  state anywhere.

  Without ClickHouse there is no history to window, so evaluation falls
  back to the legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus` — as does a device whose product has no
  profile (backfill not run).
  """

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.HealthEvaluation.Windows
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfiles

  @type status() :: :unknown | :healthy | :warning | :unhealthy
  @type reasons() :: %{warning: map(), unhealthy: map()} | nil

  @doc """
  Health status and reasons for the device described by `device_info` (a
  `NervesHub.DeviceLink.DeviceInfo`), given the metrics map of the report
  that just arrived. The report's metrics must already be saved — the
  windows are rebuilt from storage, and must include them. The report map
  itself is only judged directly on the legacy no-profile path.
  """
  @spec evaluate(struct() | map(), map()) :: {status(), reasons()}
  def evaluate(device_info, report_metrics) do
    with true <- Application.get_env(:nerves_hub, :analytics_enabled, false),
         %HealthProfile{} = profile <- HealthProfiles.resolve(device_info.product_id, platform(device_info)) do
      minute = Windows.minute(DateTime.utc_now())

      device_info
      |> windows_from_storage(profile, minute)
      |> Windows.judge(profile, minute)
      |> Enum.concat(built_in_judgements(profile, device_info))
      |> Windows.summarize()
    else
      _no_clickhouse_or_no_profile -> legacy(report_metrics)
    end
  end

  # One windowed read over the profile's longest period covers every
  # metric's windows.
  defp windows_from_storage(device_info, %HealthProfile{} = profile, minute) do
    regular = Enum.reject(profile.metrics, & &1.built_in)
    keys = Enum.map(regular, & &1.key)

    longest =
      regular
      |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
      |> Enum.max(fn -> 0 end)

    samples = Metrics.samples_since(device_info.device_id, keys, longest)

    Windows.from_samples(profile, samples, minute)
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

  defp legacy(report_metrics) do
    case HealthStatus.calculate_metrics_status(report_metrics) do
      {status, reasons} -> {status, reasons}
      status -> {status, nil}
    end
  end

  defp platform(%{firmware_metadata: %{platform: platform}}), do: platform
  defp platform(%{firmware_metadata: %{"platform" => platform}}), do: platform
  defp platform(_device_info), do: nil
end
