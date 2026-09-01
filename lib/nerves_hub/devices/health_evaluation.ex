defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Query-backed health evaluation: fetch the device's stored samples and judge
  them with the same sliding-window counting core the per-product evaluator
  uses in memory (`NervesHub.Devices.HealthEvaluator.Windows`) — one
  semantic, two ways of getting at the samples.

  This is the fallback path. In the steady state
  `NervesHub.Devices.HealthEvaluator` judges reports from its in-memory
  windows; this module is what the extension uses when that process cannot
  be reached, and it also hosts the built-in metric judgements both paths
  share ("disconnects" counts connectivity events in ClickHouse, and
  evaluates to no opinion when analytics is disabled).

  A device whose product has no profile (backfill not run) falls back to the
  legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus`.
  """

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.HealthEvaluator.Windows
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
    case HealthProfiles.resolve(device_info.product_id, platform(device_info)) do
      nil ->
        legacy(report_metrics)

      profile ->
        minute = Windows.minute(DateTime.utc_now())

        device_info
        |> windows_from_storage(profile, minute)
        |> Windows.judge(profile, minute)
        |> Enum.concat(built_in_judgements(profile, device_info))
        |> Windows.summarize()
    end
  end

  @doc """
  Rebuild a device's windows from its stored samples — one indexed query
  over the profile's longest window. Also how `HealthEvaluator` warms up a
  device it has not seen yet.
  """
  @spec windows_from_storage(struct() | map(), HealthProfile.t(), integer()) :: Windows.t()
  def windows_from_storage(device_info, %HealthProfile{} = profile, minute) do
    regular = Enum.reject(profile.metrics, & &1.built_in)
    keys = Enum.map(regular, & &1.key)

    longest =
      regular
      |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
      |> Enum.max(fn -> 0 end)

    samples = Metrics.samples_since(device_info.device_id, keys, longest)

    Windows.from_samples(profile, samples, minute)
  end

  @doc """
  Judge the profile's built-in metrics. Built-ins move independently of what
  the device reports — each has its own query.
  """
  @spec built_in_judgements(HealthProfile.t(), struct() | map()) :: [Windows.judgement()]
  def built_in_judgements(%HealthProfile{} = profile, device_info) do
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
