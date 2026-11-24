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
end
