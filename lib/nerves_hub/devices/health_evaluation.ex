defmodule NervesHub.Devices.HealthEvaluation do
  @moduledoc """
  Judges a device's health against its product's profile, as each metric
  report arrives — on the `metrics` extension or the `health` extension,
  both of which store through `NervesHub.Devices.Metrics.record/3` and
  judge through here. Stateless, per report, in the channel process: no
  cache, no process, no state anywhere.

  ## The counting semantic

  Status never needs a median's value, only which side of a threshold it
  sits, and "median >= T" is "at least half the window's samples are at or
  over T". So a level engages when its window holds at least one sample and
  at least half of them breach the threshold in the metric's unhealthy
  direction — the discrete-median reading of "the median reaches the
  threshold", which keeps the median's robustness: one absurd glitch
  reading is one vote, not a value that can drag anything. Windows are
  judged on minute buckets (unix time div 60), the evaluation granularity;
  measurement periods round up to whole minutes.

  Counting is ClickHouse's home turf, so the store is never asked for raw
  readings: `Metrics.health_breach_counts/3` returns, per metric and level,
  how many samples the window holds and how many breach — one aggregate
  query per evaluation. The judgement over those counts is a handful of
  pure functions here.

  ## Readings in hand

  `record/3` buffers its ClickHouse write, so the freshest samples are the
  ones the store cannot serve yet. The report's own readings are therefore
  counted in hand (`count_samples/3`) and merged with the stored counts —
  do not reintroduce "write then read back". Batched readings carry device
  timestamps and are bucketed where they belong, so a device reporting late
  lands its catch-up data in the right minutes.

  ## Built-ins

  A profile's built-in metrics read what the platform already keeps about
  the device — nothing here writes, and nothing asks the device for more:

    * "disconnects" counts connectivity events (ClickHouse).
    * "error_reports" counts error reports (ClickHouse); a device without
      the extension gets no opinion rather than a clean bill.
    * "update_attempts" counts firmware updates sent since the device last
      updated successfully (the device row).
    * "alarms" and "failed_checks" reduce each stored health report — and
      the one in hand, when the readings came with one — to a number, then
      judge it through the same counting semantic as a reported metric: the
      level engages when at least half the reports in the window reach the
      threshold.

  Without ClickHouse there is no history to window, so evaluation falls
  back to the legacy instantaneous check against the report itself, in
  `NervesHub.Devices.HealthStatus` — as does a device whose product has no
  profile (backfill not run).
  """

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.ErrorReports
  alias NervesHub.Extensions.PubSub, as: ExtensionsPubSub
  alias NervesHub.Helpers.Logging
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric
  alias NervesHub.Products.HealthProfiles

  require Logger

  @type status() :: :unknown | :healthy | :warning | :unhealthy
  @type reasons() :: %{warning: map(), unhealthy: map()} | nil

  @typedoc "A reading in hand: not yet readable from the store."
  @type sample() :: {key :: String.t(), DateTime.t(), value :: number()}

  @typedoc "Per metric key and level: samples in the window, samples breaching the threshold."
  @type counts() :: %{
          optional(String.t()) => %{
            warning: {non_neg_integer(), non_neg_integer()},
            alert: {non_neg_integer(), non_neg_integer()}
          }
        }

  @type judgement() :: :unknown | :healthy | {:warning | :unhealthy, key :: String.t(), reason :: map()}

  @doc """
  Health status and reasons for the device described by `device_info` (a
  `NervesHub.DeviceLink.DeviceInfo`), judging the stored history plus the
  `in_hand_samples` that just arrived and are still in the write buffer.

  `report` is the health report the readings came in, when they came in
  one: the built-ins that judge reports count it alongside the stored ones,
  since it is not stored until after judging. `nil` when the readings
  arrived on their own (the metrics extension).
  """
  @spec evaluate(struct() | map(), [sample()], map() | nil) :: {status(), reasons()}
  def evaluate(device_info, in_hand_samples, report \\ nil) do
    with true <- Application.get_env(:nerves_hub, :analytics_enabled, false),
         %HealthProfile{} = profile <- HealthProfiles.resolve(device_info) do
      now = DateTime.utc_now()
      now_minute = minute(now)
      regular = Enum.reject(profile.metrics, & &1.built_in)

      counts =
        merge_counts(
          Metrics.health_breach_counts(device_info, regular, now_minute),
          count_samples(regular, in_hand_samples, now_minute)
        )

      regular
      |> judge_metrics(counts)
      |> Enum.concat(built_in_judgements(profile, device_info, report, now))
      |> summarize()
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
    {status, reasons} = evaluate(device_info, in_hand_samples, report_data)

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

  @doc "The minute bucket for a point in time."
  @spec minute(DateTime.t()) :: integer()
  def minute(%DateTime{} = at), do: at |> DateTime.to_unix() |> div(60)

  @doc """
  Count in-hand samples into the same shape the store reports: per metric
  and level, samples in the window and samples breaching. Only the given
  (regular) metrics are counted — other keys carry no thresholds — and only
  samples whose minute bucket falls inside the level's window.
  """
  @spec count_samples([HealthProfileMetric.t()], [sample()], integer()) :: counts()
  def count_samples(metrics, samples, now_minute) do
    by_key = Map.new(metrics, &{&1.key, &1})

    Enum.reduce(samples, %{}, fn {key, at, value}, counts ->
      with %HealthProfileMetric{} = metric <- by_key[key],
           true <- is_number(value) do
        merge_counts(counts, %{key => sample_counts(metric, value, minute(at), now_minute)})
      else
        _unknown_key_or_not_a_number -> counts
      end
    end)
  end

  # One sample's contribution: a vote in each level whose window holds its
  # minute, breaching or not.
  defp sample_counts(metric, value, sample_minute, now_minute) do
    Map.new(
      [
        warning: {metric.warning_threshold, metric.warning_period_seconds},
        alert: {metric.alert_threshold, metric.alert_period_seconds}
      ],
      fn {level, {threshold, period_seconds}} ->
        if in_window?(sample_minute, now_minute, span(period_seconds)) do
          {level, {1, boolint(breaches?(value, threshold, metric.operator))}}
        else
          {level, {0, 0}}
        end
      end
    )
  end

  @doc "Merge two count maps by adding their per-level counts."
  @spec merge_counts(counts(), counts()) :: counts()
  def merge_counts(a, b) do
    Map.merge(a, b, fn _key, left, right ->
      Map.merge(left, right, fn _level, {n1, k1}, {n2, k2} -> {n1 + n2, k1 + k2} end)
    end)
  end

  @doc """
  Judge every metric against its counts: alert engages before warning, any
  observed sample beats no data. Returns judgements `summarize/1` folds, so
  callers can append built-in judgements before summarizing.
  """
  @spec judge_metrics([HealthProfileMetric.t()], counts()) :: [judgement()]
  def judge_metrics(metrics, counts) do
    Enum.map(metrics, fn metric ->
      %{warning: {n_warning, k_warning}, alert: {n_alert, k_alert}} =
        Map.get(counts, metric.key, %{warning: {0, 0}, alert: {0, 0}})

      cond do
        engaged?(n_alert, k_alert) ->
          {:unhealthy, metric.key,
           share_reason(k_alert, n_alert, metric, metric.alert_threshold, metric.alert_period_seconds)}

        engaged?(n_warning, k_warning) ->
          {:warning, metric.key,
           share_reason(k_warning, n_warning, metric, metric.warning_threshold, metric.warning_period_seconds)}

        n_warning > 0 or n_alert > 0 ->
          :healthy

        true ->
          :unknown
      end
    end)
  end

  @doc """
  Fold judgements into `{status, reasons}` in the shape `device_health`
  stores: alert (`:unhealthy`) wins over warning, any healthy metric beats
  no data, reasons name every engaged metric.
  """
  @spec summarize([judgement()]) :: {status(), reasons()}
  def summarize(judgements) do
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

  # At least one sample, and at least half of them breaching the threshold in
  # the metric's unhealthy direction: the counting form of "the (discrete)
  # median reaches the threshold".
  defp engaged?(n, k), do: n > 0 and 2 * k >= n

  # Which side of the threshold is unhealthy. `nil` (structs built before the
  # column existed) reads as :gte, the historical behavior.
  defp breaches?(value, threshold, :lte), do: value <= threshold
  defp breaches?(value, threshold, _gte_or_nil), do: value >= threshold

  defp share_reason(k, n, metric, threshold, period_seconds) do
    %{
      value: round(100 * k / n),
      threshold: threshold,
      operator: metric.operator || :gte,
      period_seconds: period_seconds,
      aggregation: :share
    }
  end

  # The window over the last `span` minutes is the buckets
  # (now - span, now] — the current, still-filling minute counts, and a
  # bucket exactly `span` minutes old has fallen out.
  defp in_window?(minute, now_minute, span), do: minute > now_minute - span

  # Periods are stored in seconds; evaluation granularity is a minute.
  defp span(period_seconds), do: div(period_seconds + 59, 60)

  defp boolint(true), do: 1
  defp boolint(false), do: 0

  # Built-ins move independently of what the device reports — each has its
  # own read.
  defp built_in_judgements(%HealthProfile{} = profile, device_info, report, now) do
    for metric <- profile.metrics, metric.built_in do
      judge_built_in(metric, device_info, report, now)
    end
  end

  # Only reached with analytics enabled: `evaluate/3` gates on it before
  # anything is judged.
  defp judge_built_in(%{key: "disconnects"} = metric, device_info, _report, _now) do
    {warning_count, alert_count} =
      Connections.disconnection_counts(
        device_info.org_id,
        device_info.product_id,
        device_info.device_id,
        periods(metric)
      )

    judge_counts(metric, warning_count, alert_count)
  end

  # Zero reports from a device that cannot send any is silence, not health.
  defp judge_built_in(%{key: "error_reports"} = metric, device_info, _report, _now) do
    if extension_allowed?(device_info, :error_reports) do
      {warning_count, alert_count} = ErrorReports.counts_for_device(device_info, periods(metric))
      judge_counts(metric, warning_count, alert_count)
    else
      :unknown
    end
  end

  defp judge_built_in(%{key: "update_attempts"} = metric, device_info, _report, now) do
    attempts = Devices.update_attempts(device_info.device_id)

    judge_counts(
      metric,
      Enum.count(attempts, &within?(&1, now, metric.warning_period_seconds)),
      Enum.count(attempts, &within?(&1, now, metric.alert_period_seconds))
    )
  end

  defp judge_built_in(%{key: "alarms"} = metric, device_info, report, now) do
    judge_reports(metric, device_info, report, now, &alarm_count/1)
  end

  defp judge_built_in(%{key: "failed_checks"} = metric, device_info, report, now) do
    judge_reports(metric, device_info, report, now, &failed_check_count/1)
  end

  # A built-in this release doesn't know how to evaluate: rows written by a
  # newer node during a rolling deploy. No opinion beats a wrong one.
  defp judge_built_in(_metric, _device_info, _report, _now), do: :unknown

  defp judge_counts(metric, warning_count, alert_count) do
    cond do
      alert_count >= metric.alert_threshold ->
        {:unhealthy, metric.key, count_reason(alert_count, metric.alert_threshold, metric.alert_period_seconds)}

      warning_count >= metric.warning_threshold ->
        {:warning, metric.key, count_reason(warning_count, metric.warning_threshold, metric.warning_period_seconds)}

      true ->
        :healthy
    end
  end

  defp count_reason(count, threshold, period_seconds) do
    %{value: count, threshold: threshold, period_seconds: period_seconds, aggregation: :count}
  end

  # The stored reports in the window plus the one in hand, each reduced to
  # one number by `count`, then counted and judged exactly like readings of
  # a metric: same buckets, same majority rule, same reason shape. A report
  # `count` has no number for (nil) says nothing, and is left out.
  defp judge_reports(metric, device_info, report, now, count) do
    stored =
      Health.reports_since(device_info.device_id, max(metric.warning_period_seconds, metric.alert_period_seconds))

    in_hand = if is_map(report), do: [{now, report}], else: []

    samples =
      for {at, data} <- in_hand ++ stored,
          value = count.(data),
          is_integer(value),
          do: {metric.key, at, value}

    [judgement] = judge_metrics([metric], count_samples([metric], samples, minute(now)))

    judgement
  end

  defp alarm_count(%{"alarms" => alarms}) when is_map(alarms), do: map_size(alarms)
  defp alarm_count(_report), do: 0

  # A report without checks has no opinion on them: checks are configured
  # per product, and most devices never send any.
  defp failed_check_count(%{"checks" => checks}) when is_map(checks) and map_size(checks) > 0 do
    Enum.count(checks, fn
      {_name, %{"pass" => true}} -> false
      _failed_or_malformed -> true
    end)
  end

  defp failed_check_count(_report), do: nil

  defp periods(metric), do: {metric.warning_period_seconds, metric.alert_period_seconds}

  defp within?(%DateTime{} = at, now, seconds), do: DateTime.diff(now, at, :second) <= seconds

  defp extension_allowed?(device_info, extension) do
    extension in (Map.get(device_info, :allowed_extensions) || [])
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
end
