defmodule NervesHub.Devices.HealthEvaluation.Screen do
  @moduledoc """
  Decides when a health report cannot possibly change a device's status, so
  the windowed aggregate queries can be skipped.

  Most of a healthy fleet's reports are all-clear — every profile metric
  below its warning threshold — and evaluating each one costs a
  `percentile_cont` window query (plus a ClickHouse count per built-in).
  This screen removes that cost for the steady state.

  The rule has to be exact, and "healthy device + all-clear report" alone is
  not: samples *leaving* the window matter too. A window holding old low
  samples and newer high ones can have its median rise purely by the low
  samples aging out — no new high sample required. What is exact: if every
  sample in a window is below the threshold, its median is below the
  threshold. So the screen skips only when the device has reported nothing
  but all-clear values for at least the profile's longest measurement
  period — then every sample in every window came from an all-clear report,
  and the evaluation's outcome is known without running it.

  The streak is tracked per connection (in the extension's assigns), which
  makes it conservative in exactly the right places: a reconnect, a restart,
  or a profile edit (detected by fingerprint) resets it, and the next report
  evaluates for real.

  A profile containing a built-in metric never skips: built-ins (e.g.
  disconnect counts) move independently of what the device reports, so a
  report carries no evidence about them.
  """

  alias NervesHub.Products.HealthProfile

  defstruct all_clear_since: nil,
            last_reasons: nil,
            last_status: nil,
            profile_fingerprint: nil

  @type t :: %__MODULE__{
          last_status: :unknown | :healthy | :warning | :unhealthy | nil,
          last_reasons: map() | nil,
          all_clear_since: DateTime.t() | nil,
          profile_fingerprint: non_neg_integer() | nil
        }

  def new(), do: %__MODULE__{}

  @doc """
  Whether evaluation of this report can be skipped: the device is healthy,
  the report is all-clear, and the all-clear streak already spans the
  profile's longest measurement period.
  """
  @spec skip?(t(), HealthProfile.t(), map(), DateTime.t()) :: boolean()
  def skip?(%__MODULE__{} = screen, %HealthProfile{} = profile, report_metrics, now) do
    {built_ins, regular} = Enum.split_with(profile.metrics, & &1.built_in)

    screen.last_status == :healthy and
      built_ins == [] and
      regular != [] and
      screen.profile_fingerprint == fingerprint(profile) and
      reports_a_profile_metric?(regular, report_metrics) and
      all_clear?(regular, report_metrics) and
      streak_covers_windows?(screen, regular, now)
  end

  @doc """
  Fold this report's outcome into the screen: advance or reset the all-clear
  streak, and remember the status the next report may carry forward.

  `status`/`reasons` are whatever this report ended up with — freshly
  evaluated or carried forward from a skip.
  """
  @spec observe(t(), HealthProfile.t() | nil, map(), atom(), map() | nil, DateTime.t()) :: t()
  def observe(%__MODULE__{} = screen, profile, report_metrics, status, reasons, now) do
    fingerprint = profile && fingerprint(profile)

    all_clear_since =
      cond do
        is_nil(profile) -> nil
        screen.profile_fingerprint != fingerprint -> start_streak(profile, report_metrics, now)
        all_clear?(regular_metrics(profile), report_metrics) -> screen.all_clear_since || now
        true -> nil
      end

    %__MODULE__{
      last_status: status,
      last_reasons: reasons,
      all_clear_since: all_clear_since,
      profile_fingerprint: fingerprint
    }
  end

  # A profile edit invalidates the streak: its values were "clear" against
  # thresholds that no longer apply. The current report can still open a new
  # streak against the new thresholds.
  defp start_streak(profile, report_metrics, now) do
    if all_clear?(regular_metrics(profile), report_metrics), do: now
  end

  defp regular_metrics(profile), do: Enum.reject(profile.metrics, & &1.built_in)

  # Every profile metric present in the report is strictly below its warning
  # threshold. Strictly: a level engages at value >= threshold, so a sample
  # equal to the threshold is evidence, not clearance. A non-numeric value is
  # not clearance either.
  defp all_clear?(regular, report_metrics) do
    Enum.all?(regular, fn metric ->
      case Map.fetch(report_metrics, metric.key) do
        {:ok, value} -> is_number(value) and value < metric.warning_threshold
        :error -> true
      end
    end)
  end

  # The skipped evaluation must be for a report that carries at least one
  # profile metric: it keeps fresh in-window data on the books, so the true
  # status cannot drift to :unknown while the stored one says :healthy.
  defp reports_a_profile_metric?(regular, report_metrics) do
    Enum.any?(regular, &Map.has_key?(report_metrics, &1.key))
  end

  # The streak must span the longest window in the profile, so that every
  # sample any window can still contain arrived during the streak.
  defp streak_covers_windows?(%{all_clear_since: nil}, _regular, _now), do: false

  defp streak_covers_windows?(%{all_clear_since: since}, regular, now) do
    longest =
      regular
      |> Enum.flat_map(&[&1.warning_period_seconds, &1.alert_period_seconds])
      |> Enum.max()

    DateTime.diff(now, since, :second) >= longest
  end

  @doc """
  A stable digest of everything about a profile that the streak's soundness
  depends on. Thresholds and periods, but also membership: a metric added to
  the profile mid-streak was never checked by it.
  """
  @spec fingerprint(HealthProfile.t()) :: non_neg_integer()
  def fingerprint(%HealthProfile{} = profile) do
    profile.metrics
    |> Enum.map(
      &{&1.key, &1.built_in, &1.warning_threshold, &1.warning_period_seconds, &1.alert_threshold,
       &1.alert_period_seconds}
    )
    |> Enum.sort()
    |> then(&:erlang.phash2({profile.id, &1}))
  end
end
