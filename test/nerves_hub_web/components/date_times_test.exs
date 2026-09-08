defmodule NervesHubWeb.Components.DateTimesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHubWeb.Components.DateTimes

  # 05:00 UTC is the evening of the 2nd in Auckland but still the 1st in Los
  # Angeles, so a rendering that quietly stayed in UTC can't pass by accident.
  @at ~U[2026-01-02 05:00:00Z]

  defp render_at(assigns) do
    render_component(&DateTimes.local_datetime/1, Map.merge(%{at: @at}, assigns))
  end

  describe "local_datetime/1" do
    test "renders the timestamp in the given zone" do
      assert render_at(%{time_zone: "Pacific/Auckland"}) =~ "2026-01-02 at 6:00 PM NZDT"
      assert render_at(%{time_zone: "America/Los_Angeles"}) =~ "2026-01-01 at 9:00 PM PST"
    end

    test "falls back to UTC when the zone is missing or unrecognised" do
      assert render_at(%{time_zone: nil}) =~ "2026-01-02 at 5:00 AM UTC"
      assert render_at(%{time_zone: "Mars/Olympus_Mons"}) =~ "2026-01-02 at 5:00 AM UTC"
    end

    test "keeps the original UTC value in the title, for cross-referencing logs" do
      html = render_at(%{time_zone: "Pacific/Auckland"})

      assert html =~ ~s|title="2026-01-02 05:00:00 UTC"|
      assert html =~ ~s|datetime="2026-01-02T05:00:00Z"|
    end

    test "omits the zone label on request" do
      html = render_at(%{time_zone: "Pacific/Auckland", format: :date, zone_label: false})

      assert html =~ ">2026-01-02<"
      refute html =~ "NZDT"
    end

    test "supports every declared format" do
      opts = %{time_zone: "Pacific/Auckland", zone_label: false}

      assert render_at(Map.put(opts, :format, :date)) =~ ">2026-01-02<"
      assert render_at(Map.put(opts, :format, :long_date)) =~ ">January 2, 2026<"
      assert render_at(Map.put(opts, :format, :long_datetime)) =~ ">January 2, 2026 6:00 PM<"
      assert render_at(Map.put(opts, :format, :datetime)) =~ ">2026-01-02 at 6:00 PM<"
      assert render_at(Map.put(opts, :format, :datetime_seconds)) =~ ">2026-01-02 at 6:00:00 PM<"
      assert render_at(Map.put(opts, :format, :timestamp)) =~ ">2026-01-02 18:00:00<"
      assert render_at(Map.put(opts, :format, :short_timestamp)) =~ ">2026-01-02 18:00<"
      assert render_at(Map.put(opts, :format, :time)) =~ ">6:00 PM<"
      assert render_at(Map.put(opts, :format, :log)) =~ ">2026-01-02 18:00:00.000<"
    end

    test "pads log milliseconds, so lines stay column-aligned" do
      opts = %{time_zone: "Etc/UTC", format: :log, zone_label: false}

      assert render_at(Map.put(opts, :at, ~U[2026-01-02 05:00:00.007000Z])) =~ "05:00:00.007"
      assert render_at(Map.put(opts, :at, ~U[2026-01-02 05:00:00.123456Z])) =~ "05:00:00.123"
    end

    test "treats a NaiveDateTime as UTC" do
      html = render_at(%{at: ~N[2026-01-02 05:00:00], time_zone: "Pacific/Auckland"})

      assert html =~ "2026-01-02 at 6:00 PM NZDT"
    end

    test "renders the fallback instead of a <time> element when there is no timestamp" do
      html = render_at(%{at: nil, time_zone: "Pacific/Auckland", fallback: "Never"})

      assert html =~ "Never"
      refute html =~ "<time"
    end

    test "passes global attributes through" do
      assert render_at(%{time_zone: "Etc/UTC", class: "text-xs"}) =~ ~s|class="text-xs"|
    end
  end

  describe "zone_abbr/1" do
    test "names the zone, for labelling a table column once" do
      assert DateTimes.zone_abbr("Etc/UTC") == "UTC"
      assert DateTimes.zone_abbr("Pacific/Auckland") in ["NZST", "NZDT"]
    end

    test "falls back to UTC for a zone the database doesn't know" do
      assert DateTimes.zone_abbr("Mars/Olympus_Mons") == "UTC"
      assert DateTimes.zone_abbr(nil) == "UTC"
    end
  end

  describe "to_local_string/4" do
    test "formats in the given zone" do
      assert DateTimes.to_local_string(@at, "Pacific/Auckland", :long_datetime) ==
               "January 2, 2026 6:00 PM NZDT"
    end

    test "returns nil when there is no timestamp" do
      assert DateTimes.to_local_string(nil, "Pacific/Auckland") == nil
    end
  end
end
