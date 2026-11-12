defmodule NervesHubWeb.Components.DeviceHealth.AlarmsRowTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHubWeb.Components.DeviceHealth.AlarmsRow

  defp row(alarms, time_zone \\ "UTC") do
    render_component(&AlarmsRow.render/1, %{id: "alarms", alarms: alarms, time_zone: time_zone})
  end

  test "says when an alarm raised today started, as a time" do
    raised_at = DateTime.utc_now()
    time = Calendar.strftime(raised_at, "%-I:%M %p")

    assert row([{"DiskAlmostFull", nil, raised_at}]) =~ ~r/since\s+<time[^>]*>#{time}<\/time>/
  end

  test "gives the date as well for an alarm raised before today" do
    html = row([{"DiskAlmostFull", "/data", ~U[2026-03-05 22:41:17.000000Z]}])

    assert html =~ ~r/since\s+<time[^>]*>Mar 5, 10:41 PM<\/time>/
  end

  test "says when it started in the viewer's zone" do
    html = row([{"DiskAlmostFull", nil, ~U[2026-03-05 22:41:17.000000Z]}], "America/New_York")

    assert html =~ ~r/since\s+<time[^>]*>Mar 5, 5:41 PM<\/time>/
  end

  test "says none are active when there are none" do
    assert row(nil) =~ "None active"
  end
end
