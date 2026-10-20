defmodule NervesHub.Helpers.RelativeTimeTest do
  use ExUnit.Case, async: true

  alias NervesHub.Helpers.RelativeTime

  doctest RelativeTime

  @now ~U[2026-06-15 12:00:00Z]

  defp from_now(seconds), do: RelativeTime.from_now(DateTime.add(@now, seconds), @now)

  test "describes the past" do
    assert from_now(-1) == "1 second ago"
    assert from_now(-45) == "45 seconds ago"
    assert from_now(-46) == "1 minute ago"
    assert from_now(-120) == "2 minutes ago"
    assert from_now(-3600) == "1 hour ago"
    assert from_now(-7200) == "2 hours ago"
    assert from_now(-86_400) == "yesterday"
    assert from_now(-2 * 86_400) == "2 days ago"
    assert from_now(-30 * 86_400) == "1 month ago"
    assert from_now(-60 * 86_400) == "2 months ago"
    assert from_now(-360 * 86_400) == "1 year ago"
    assert from_now(-720 * 86_400) == "2 years ago"
  end

  test "describes the future" do
    assert from_now(0) == "now"
    assert from_now(1) == "in 1 second"
    assert from_now(90) == "in 1 minute"
    assert from_now(5400) == "in 1 hour"
    assert from_now(86_400) == "tomorrow"
    assert from_now(3 * 86_400) == "in 3 days"
    assert from_now(400 * 86_400) == "in 1 year"
  end

  test "counts whole seconds, truncated toward zero" do
    assert RelativeTime.from_now(DateTime.add(@now, -900, :millisecond), @now) == "now"
    assert RelativeTime.from_now(DateTime.add(@now, -1900, :millisecond), @now) == "1 second ago"
  end

  test "takes a NaiveDateTime to be in UTC" do
    assert RelativeTime.from_now(~N[2026-06-15 09:00:00], @now) == "3 hours ago"
  end

  test "compares a DateTime in another zone by its UTC time" do
    datetime = %DateTime{
      year: 2026,
      month: 6,
      day: 15,
      hour: 11,
      minute: 0,
      second: 0,
      microsecond: {0, 0},
      time_zone: "Europe/Berlin",
      zone_abbr: "CEST",
      utc_offset: 3600,
      std_offset: 3600
    }

    assert RelativeTime.from_now(datetime, @now) == "3 hours ago"
  end
end
