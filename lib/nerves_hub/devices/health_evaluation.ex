defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Evaluates a device's health against its product's health profile.

  Runs as each health report arrives (after the report's metrics are saved, so
  the window includes them): the profile is resolved for the device's product
  and platform, and each profile metric's average over its measurement period
  is compared to its thresholds. A level engages at average >= threshold;
  alert (stored as `:unhealthy`) takes precedence over warning. Averaging over
  the period rather than judging the latest sample means a single spike only
  trips a level when it is large enough to pull the whole window over.

  Built-in profile metrics are not averaged from `device_metrics`; each has
  its own query. "disconnects" counts connectivity events in the period, and
  evaluates to no opinion when analytics is disabled.

  A device whose product has no profile (backfill not run) falls back to the
  legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus`.
  """

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Products.HealthProfiles

  @type status() :: :unknown | :healthy | :warning | :unhealthy
  @type reasons() :: %{warning: map(), unhealthy: map()} | nil

  @doc """
  Health status and reasons for the device described by `device_info` (a
  `NervesHub.DeviceLink.DeviceInfo`), given the metrics map of the report that
  just arrived (used only by the legacy fallback).
  """
  @spec evaluate(struct() | map(), map()) :: {status(), reasons()}
  def evaluate(device_info, report_metrics) do
    case HealthProfiles.resolve(device_info.product_id, platform(device_info)) do
      nil ->
        legacy(report_metrics)

      profile ->
        evaluate_profile(device_info, profile)
    end
  end

  defp evaluate_profile(device_info, profile) do
    {built_ins, regular} = Enum.split_with(profile.metrics, & &1.built_in)

    averages = averages(device_info.device_id, regular)

    regular
    |> Enum.map(fn metric ->
      judge(
        metric,
        averages[{metric.key, metric.warning_period_minutes}],
        averages[{metric.key, metric.alert_period_minutes}]
      )
    end)
    |> Enum.concat(Enum.map(built_ins, &judge_built_in(&1, device_info)))
    |> summarize()
  end

  # One query per distinct measurement period covers every metric window: a
  # metric's warning and alert periods usually coincide, and periods repeat
  # across metrics.
  defp averages(device_id, metrics) do
    metrics
    |> Enum.flat_map(&[{&1.key, &1.warning_period_minutes}, {&1.key, &1.alert_period_minutes}])
    |> Enum.group_by(fn {_key, period} -> period end, fn {key, _period} -> key end)
    |> Enum.flat_map(fn {period, keys} ->
      device_id
      |> Metrics.average_values(Enum.uniq(keys), period)
      |> Enum.map(fn {key, avg} -> {{key, period}, avg} end)
    end)
    |> Map.new()
  end

  defp judge(metric, warning_avg, alert_avg) do
    cond do
      is_number(alert_avg) and alert_avg >= metric.alert_threshold ->
        {:unhealthy, metric.key, reason(alert_avg, metric.alert_threshold, metric.alert_period_minutes)}

      is_number(warning_avg) and warning_avg >= metric.warning_threshold ->
        {:warning, metric.key, reason(warning_avg, metric.warning_threshold, metric.warning_period_minutes)}

      is_number(warning_avg) or is_number(alert_avg) ->
        :healthy

      true ->
        :unknown
    end
  end

  defp judge_built_in(%{key: "disconnects"} = metric, device_info) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      count = fn minutes ->
        Connections.disconnection_count(
          device_info.org_id,
          device_info.product_id,
          device_info.device_id,
          minutes
        )
      end

      judge(metric, count.(metric.warning_period_minutes), count.(metric.alert_period_minutes))
    else
      :unknown
    end
  end

  # A built-in this release doesn't know how to evaluate: rows written by a
  # newer node during a rolling deploy. No opinion beats a wrong one.
  defp judge_built_in(_metric, _device_info), do: :unknown

  defp reason(value, threshold, period_minutes) do
    %{value: round_value(value), threshold: threshold, period_minutes: period_minutes}
  end

  defp round_value(value) when is_float(value), do: Float.round(value, 2)
  defp round_value(value), do: value

  defp summarize(judgements) do
    reasons =
      Enum.reduce(judgements, %{warning: %{}, unhealthy: %{}}, fn
        {level, key, reason}, acc -> put_in(acc, [level, key], reason)
        _healthy_or_unknown, acc -> acc
      end)

    cond do
      reasons.unhealthy != %{} -> {:unhealthy, reasons}
      reasons.warning != %{} -> {:warning, reasons}
      Enum.any?(judgements, &(&1 == :healthy)) -> {:healthy, nil}
      true -> {:unknown, nil}
    end
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
