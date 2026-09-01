defmodule NervesHub.Devices.HealthEvaluator.Windows do
  @moduledoc """
  Sliding-window majority counters for one device's health metrics — the pure
  core of `NervesHub.Devices.HealthEvaluator`.

  The insight that makes this cheap: status never needs the median's value,
  only which side of a fixed threshold it sits, and "median >= T" is "at
  least half the samples are at or over T". That turns the windowed
  percentile into windowed counting, and counting — unlike a median — is
  invertible: a sample leaving the window is a subtraction. So the state per
  (metric) is a handful of per-minute buckets, each holding how many samples
  landed in that minute and how many of them were at or over each threshold,
  and every operation is O(buckets).

  Buckets are keyed by absolute minute (unix time divided by 60), matching
  the one-minute evaluation granularity; measurement periods round up to
  whole minutes. A level engages when its window holds at least one sample
  and at least half of them are at or over the threshold — the
  discrete-median reading of "the median reaches the threshold", which also
  keeps the median's robustness: one absurd glitch reading is one vote, not
  a value that can drag anything.
  """

  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric

  @typedoc "metric key => %{minute => {samples, at_or_over_warning, at_or_over_alert}}"
  @type t :: %{optional(String.t()) => %{optional(integer()) => {pos_integer(), non_neg_integer(), non_neg_integer()}}}

  @type judgement ::
          :unknown
          | :healthy
          | {:warning | :unhealthy, key :: String.t(), reason :: map()}

  def new(), do: %{}

  @doc "The bucket for a point in time."
  @spec minute(DateTime.t()) :: integer()
  def minute(%DateTime{} = at), do: at |> DateTime.to_unix() |> div(60)

  @doc """
  Count this report's values into the current minute's buckets. Only the
  profile's regular (non-built-in) metrics are tracked; other keys carry no
  thresholds to count against.
  """
  @spec record(t(), HealthProfile.t(), map(), integer()) :: t()
  def record(windows, %HealthProfile{} = profile, values, minute) do
    profile
    |> regular_metrics()
    |> Enum.reduce(windows, fn metric, acc ->
      case Map.fetch(values, metric.key) do
        {:ok, value} when is_number(value) -> record_sample(acc, metric, value, minute)
        _absent_or_not_a_number -> acc
      end
    end)
  end

  @doc """
  Rebuild windows from stored samples, for a device this evaluator has not
  seen yet. Samples older than a metric's longest window are not kept.
  """
  @spec from_samples(HealthProfile.t(), [{String.t(), DateTime.t(), number()}], integer()) :: t()
  def from_samples(%HealthProfile{} = profile, samples, now_minute) do
    metrics = profile |> regular_metrics() |> Map.new(&{&1.key, &1})

    Enum.reduce(samples, new(), fn {key, at, value}, acc ->
      with %HealthProfileMetric{} = metric <- metrics[key],
           sample_minute = minute(at),
           true <- in_window?(sample_minute, now_minute, longest_span(metric)),
           true <- is_number(value) do
        record_sample(acc, metric, value, sample_minute)
      else
        _ -> acc
      end
    end)
  end

  @doc "Drop buckets no window can reach any more."
  @spec prune(t(), HealthProfile.t(), integer()) :: t()
  def prune(windows, %HealthProfile{} = profile, now_minute) do
    spans = profile |> regular_metrics() |> Map.new(&{&1.key, longest_span(&1)})

    windows
    |> Enum.map(fn {key, buckets} ->
      # A key no longer in the profile keeps nothing.
      span = Map.get(spans, key, 0)
      {key, Map.filter(buckets, fn {minute, _counts} -> in_window?(minute, now_minute, span) end)}
    end)
    |> Enum.reject(fn {_key, buckets} -> buckets == %{} end)
    |> Map.new()
  end

  @doc """
  Judge every regular metric of the profile against its windows.

  Returns judgements in the same shape `summarize/1` folds, so callers can
  append built-in judgements before summarizing.
  """
  @spec judge(t(), HealthProfile.t(), integer()) :: [judgement()]
  def judge(windows, %HealthProfile{} = profile, now_minute) do
    Enum.map(regular_metrics(profile), fn metric ->
      buckets = Map.get(windows, metric.key, %{})

      {n_alert, k_alert} = window_counts(buckets, now_minute, span(metric.alert_period_seconds), :alert)
      {n_warning, k_warning} = window_counts(buckets, now_minute, span(metric.warning_period_seconds), :warning)

      cond do
        engaged?(n_alert, k_alert) ->
          {:unhealthy, metric.key, reason(k_alert, n_alert, metric.alert_threshold, metric.alert_period_seconds)}

        engaged?(n_warning, k_warning) ->
          {:warning, metric.key, reason(k_warning, n_warning, metric.warning_threshold, metric.warning_period_seconds)}

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
  @spec summarize([judgement()]) :: {:unknown | :healthy | :warning | :unhealthy, map() | nil}
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

  # At least one sample, and at least half of them at or over the threshold:
  # the counting form of "the (discrete) median reaches the threshold".
  defp engaged?(n, k), do: n > 0 and 2 * k >= n

  defp reason(k, n, threshold, period_seconds) do
    %{
      value: round(100 * k / n),
      threshold: threshold,
      period_seconds: period_seconds,
      aggregation: :share
    }
  end

  defp record_sample(windows, metric, value, minute) do
    over_warning = boolint(value >= metric.warning_threshold)
    over_alert = boolint(value >= metric.alert_threshold)

    windows
    |> Map.put_new(metric.key, %{})
    |> update_in([metric.key, Access.key(minute, {0, 0, 0})], fn {n, k_warning, k_alert} ->
      {n + 1, k_warning + over_warning, k_alert + over_alert}
    end)
  end

  defp window_counts(buckets, now_minute, span, level) do
    Enum.reduce(buckets, {0, 0}, fn {minute, {n, k_warning, k_alert}}, {total, over} ->
      if in_window?(minute, now_minute, span) do
        {total + n, over + if(level == :warning, do: k_warning, else: k_alert)}
      else
        {total, over}
      end
    end)
  end

  # The window over the last `span` minutes is the buckets
  # (now - span, now] — the current, still-filling minute counts, and a
  # bucket exactly `span` minutes old has fallen out.
  defp in_window?(minute, now_minute, span), do: minute > now_minute - span

  # Periods are stored in seconds; evaluation granularity is a minute.
  defp span(period_seconds), do: div(period_seconds + 59, 60)

  defp longest_span(metric), do: span(max(metric.warning_period_seconds, metric.alert_period_seconds))

  defp regular_metrics(profile), do: Enum.reject(profile.metrics, & &1.built_in)

  defp boolint(true), do: 1
  defp boolint(false), do: 0
end
