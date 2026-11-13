defmodule NervesHub.Helpers.RelativeTime do
  @moduledoc """
  Describes a time relative to now, such as "3 hours ago" or "in 2 days".

  The thresholds and wording are the ones Timex's `from_now/1` used, so
  pages and audit logs read as they did before Timex was removed.
  """

  @minute 60
  @hour @minute * 60
  @day @hour * 24
  @month @day * 30
  @year @month * 12

  @doc """
  Describes `datetime` relative to `reference`, which defaults to now.

  A `NaiveDateTime` is taken to be in UTC.

      iex> now = ~U[2026-01-10 12:00:00Z]
      iex> NervesHub.Helpers.RelativeTime.from_now(~U[2026-01-10 09:00:00Z], now)
      "3 hours ago"
      iex> NervesHub.Helpers.RelativeTime.from_now(~N[2026-01-11 13:00:00], now)
      "tomorrow"
      iex> NervesHub.Helpers.RelativeTime.from_now(~U[2026-01-12 12:00:00Z], now)
      "in 2 days"
  """
  @spec from_now(DateTime.t() | NaiveDateTime.t(), DateTime.t() | NaiveDateTime.t()) :: String.t()
  def from_now(datetime, reference \\ DateTime.utc_now()) do
    # Whole seconds, truncated toward zero, as Timex counted them.
    diff = div(DateTime.diff(to_utc(datetime), to_utc(reference), :microsecond), 1_000_000)

    cond do
      diff == 0 -> "now"
      diff >= @day and diff < @day * 2 -> "tomorrow"
      diff <= -@day and diff > -@day * 2 -> "yesterday"
      diff > 0 -> "in " <> describe(diff)
      true -> describe(-diff) <> " ago"
    end
  end

  defp to_utc(%DateTime{} = datetime), do: datetime
  defp to_utc(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp describe(seconds) when seconds <= 45, do: count(seconds, "second")
  defp describe(seconds) when seconds < @minute * 2, do: count(1, "minute")
  defp describe(seconds) when seconds < @hour, do: count(div(seconds, @minute), "minute")
  defp describe(seconds) when seconds < @hour * 2, do: count(1, "hour")
  defp describe(seconds) when seconds < @day, do: count(div(seconds, @hour), "hour")
  defp describe(seconds) when seconds < @month, do: count(div(seconds, @day), "day")
  defp describe(seconds) when seconds < @month * 2, do: count(1, "month")
  defp describe(seconds) when seconds < @year, do: count(div(seconds, @month), "month")
  defp describe(seconds) when seconds < @year * 2, do: count(1, "year")
  defp describe(seconds), do: count(div(seconds, @year), "year")

  defp count(1, unit), do: "1 #{unit}"
  defp count(n, unit), do: "#{n} #{unit}s"
end
