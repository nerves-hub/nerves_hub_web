defmodule NervesHubWeb.Components.DevicePage.ConnectionLaneTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHub.Devices.ConnectionTimeline
  alias NervesHubWeb.Components.DevicePage.ConnectionLane

  @from ~U[2026-11-17 00:00:00Z]
  @until ~U[2026-11-24 00:00:00Z]

  test "draws one tick per tenth of a percent however often a device reconnects" do
    # A reconnect every ten seconds for a week.
    reconnects = for seconds <- 10..(7 * 24 * 3600 - 10)//10, do: DateTime.add(@from, seconds)
    timeline = %ConnectionTimeline{offline: [], reconnects: reconnects}

    html =
      render_component(&ConnectionLane.lane/1,
        id: "lane",
        timeline: timeline,
        from: @from,
        until: @until,
        time_zone: "Etc/UTC"
      )

    ticks = html |> LazyHTML.from_fragment() |> LazyHTML.query("span.bg-reconnect-tick[style]") |> Enum.count()

    assert ticks <= 1001
    assert html =~ ">#{length(reconnects)}</span>"
  end

  test "draws offline spans too close together to tell apart as one" do
    # Online for a minute, then offline for a minute and a half, all week.
    offline =
      for start <- 60..(7 * 24 * 3600 - 300)//150 do
        %{
          from: DateTime.add(@from, start),
          until: DateTime.add(@from, start + 90),
          reason: "",
          interface: "wifi",
          ip_address: nil
        }
      end

    timeline = %ConnectionTimeline{offline: offline, reconnects: []}

    html =
      render_component(&ConnectionLane.lane/1,
        id: "lane",
        timeline: timeline,
        from: @from,
        until: @until,
        time_zone: "Etc/UTC"
      )

    spans = html |> LazyHTML.from_fragment() |> LazyHTML.query("button[data-offline-span]") |> Enum.count()

    assert spans == 1
    assert html =~ "Offline #{length(offline)} times"
    assert html =~ "Zoom in on the charts to see each one"
    assert html =~ ">#{length(offline)}</span>"
  end

  test "keeps offline spans apart when there's room between them" do
    offline = [
      %{
        from: DateTime.add(@from, 1, :hour),
        until: DateTime.add(@from, 2, :hour),
        reason: "Stale connection",
        interface: "wifi",
        ip_address: nil
      },
      %{
        from: DateTime.add(@from, 1, :day),
        until: DateTime.add(@from, 25, :hour),
        reason: "",
        interface: nil,
        ip_address: nil
      }
    ]

    html =
      render_component(&ConnectionLane.lane/1,
        id: "lane",
        timeline: %ConnectionTimeline{offline: offline},
        from: @from,
        until: @until,
        time_zone: "Etc/UTC"
      )

    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("button[data-offline-span]") |> Enum.count() == 2
    assert html =~ "Stopped sending heartbeats"
    refute html =~ "times"
  end
end
