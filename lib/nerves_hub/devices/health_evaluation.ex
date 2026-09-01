defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Evaluates a device's health against its product's health profile.

  Runs as each health report arrives (after the report's metrics are saved, so
  the window includes them): the profile is resolved for the device's product
  and platform, and each profile metric's median over its measurement period
  is compared to its thresholds. A level engages at median >= threshold;
  alert (stored as `:unhealthy`) takes precedence over warning. The median,
  not the mean: embedded sensors glitch, and one absurd reading (a cheap
  temperature sensor catching interference and reporting 17000) would drag a
  mean over any threshold for as long as it stays in the window, while the
  median never moves for it. It also means a short spike only engages a level
  once it holds for more than half the window.

  Built-in profile metrics don't read `device_metrics`; each has its own
  query, with its own aggregation. "disconnects" counts connectivity events
  in the period, and evaluates to no opinion when analytics is disabled.

  A device whose product has no profile (backfill not run) falls back to the
  legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus`.
  """

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.HealthEvaluation.Screen
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

  @doc """
  Like `evaluate/2`, but screened: when the `Screen` proves this report
  cannot change the status — the device has reported nothing but all-clear
  values for longer than the profile's longest measurement window — the
  windowed aggregate queries are skipped and the previous status carried
  forward. Returns the advanced screen along with the status, for the caller
  to hold onto between reports.
  """
  @spec evaluate(struct() | map(), map(), Screen.t()) :: {status(), reasons(), Screen.t()}
  def evaluate(device_info, report_metrics, %Screen{} = screen) do
    profile = HealthProfiles.resolve(device_info.product_id, platform(device_info))
    now = DateTime.utc_now()

    {status, reasons} =
      cond do
        is_nil(profile) ->
          legacy(report_metrics)

        Screen.skip?(screen, profile, report_metrics, now) ->
          # The skip requires last_status == :healthy, so this carries forward
          # a healthy verdict, never an engaged one.
          {:healthy, screen.last_reasons}

        true ->
          evaluate_profile(device_info, profile)
      end

    {status, reasons, Screen.observe(screen, profile, report_metrics, status, reasons, now)}
  end

  defp evaluate_profile(device_info, profile) do
    {built_ins, regular} = Enum.split_with(profile.metrics, & &1.built_in)

    medians = medians(device_info.device_id, regular)

    regular
    |> Enum.map(fn metric ->
      judge(
        metric,
        medians[{metric.key, metric.warning_period_seconds}],
        medians[{metric.key, metric.alert_period_seconds}],
        :median
      )
    end)
    |> Enum.concat(Enum.map(built_ins, &judge_built_in(&1, device_info)))
    |> summarize()
  end

  # One query per distinct measurement period covers every metric window: a
  # metric's warning and alert periods usually coincide, and periods repeat
  # across metrics.
  defp medians(device_id, metrics) do
    metrics
    |> Enum.flat_map(&[{&1.key, &1.warning_period_seconds}, {&1.key, &1.alert_period_seconds}])
    |> Enum.group_by(fn {_key, period} -> period end, fn {key, _period} -> key end)
    |> Enum.flat_map(fn {period, keys} ->
      device_id
      |> Metrics.median_values(Enum.uniq(keys), period)
      |> Enum.map(fn {key, median} -> {{key, period}, median} end)
    end)
    |> Map.new()
  end

  defp judge(metric, warning_value, alert_value, aggregation) do
    cond do
      is_number(alert_value) and alert_value >= metric.alert_threshold ->
        {:unhealthy, metric.key, reason(alert_value, metric.alert_threshold, metric.alert_period_seconds, aggregation)}

      is_number(warning_value) and warning_value >= metric.warning_threshold ->
        {:warning, metric.key,
         reason(warning_value, metric.warning_threshold, metric.warning_period_seconds, aggregation)}

      is_number(warning_value) or is_number(alert_value) ->
        :healthy

      true ->
        :unknown
    end
  end

  defp judge_built_in(%{key: "disconnects"} = metric, device_info) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      count = fn seconds ->
        Connections.disconnection_count(
          device_info.org_id,
          device_info.product_id,
          device_info.device_id,
          seconds
        )
      end

      judge(metric, count.(metric.warning_period_seconds), count.(metric.alert_period_seconds), :count)
    else
      :unknown
    end
  end

  # A built-in this release doesn't know how to evaluate: rows written by a
  # newer node during a rolling deploy. No opinion beats a wrong one.
  defp judge_built_in(_metric, _device_info), do: :unknown

  # `aggregation` says what `value` is (:median of the reported samples, or a
  # :count of events) so the UI can phrase the reason accordingly.
  defp reason(value, threshold, period_seconds, aggregation) do
    %{value: round_value(value), threshold: threshold, period_seconds: period_seconds, aggregation: aggregation}
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
