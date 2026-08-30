defmodule NervesHubWeb.Components.DeviceUpdateStatusTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.Device
  alias NervesHubWeb.Components.DeviceUpdateStatus

  defp future(seconds) do
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  describe "render/1" do
    test "renders penalty-box SVG when device is in penalty box" do
      device = %Device{
        id: 1,
        updates_enabled: true,
        updates_blocked_until: future(3600)
      }

      rendered = Phoenix.LiveViewTest.rendered_to_string(DeviceUpdateStatus.render(%{device: device}))
      assert String.contains?(rendered, "stroke-warning")
    end

    test "renders enabled SVG when updates are enabled and not penalized" do
      device = %Device{
        id: 2,
        updates_enabled: true,
        updates_blocked_until: nil
      }

      rendered = Phoenix.LiveViewTest.rendered_to_string(DeviceUpdateStatus.render(%{device: device}))
      assert String.contains?(rendered, "stroke-success")
    end

    test "renders disabled SVG when updates are disabled" do
      device = %Device{
        id: 3,
        updates_enabled: false,
        updates_blocked_until: nil
      }

      rendered = Phoenix.LiveViewTest.rendered_to_string(DeviceUpdateStatus.render(%{device: device}))
      assert String.contains?(rendered, "stroke-alert")
    end
  end

  describe "friendly_blocked_until/1" do
    test "< 60s → 'for less than a minute'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(30)) == "for less than a minute"
    end

    test "~90s (between 60s and 2 min) → 'for around a minute'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(90)) == "for around a minute"
    end

    test "~5 minutes → 'for 5 minutes'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(5 * 60 + 5)) == "for 5 minutes"
    end

    test "~57 minutes (between 55 and 60 min) → 'for less than an hour'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(57 * 60 + 5)) == "for less than an hour"
    end

    test "~61 minutes (between 60 and 63 min) → 'for an hour'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(61 * 60 + 5)) == "for an hour"
    end

    test "~75 minutes (between 63 and 80 min) → 'for just over an hour'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(75 * 60 + 5)) == "for just over an hour"
    end

    test "~95 minutes (between 80 and 100 min) → 'for an hour and a half'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(95 * 60 + 5)) == "for an hour and a half"
    end

    test "~105 minutes (between 100 and 110 min) → 'for around 2 hours'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(105 * 60 + 5)) == "for around 2 hours"
    end

    test "~5 hours (between 2h and 24h) → 'for 5 hours'" do
      assert DeviceUpdateStatus.friendly_blocked_until(future(5 * 3600 + 5)) == "for 5 hours"
    end

    test "2+ days → 'until <formatted date>'" do
      blocked_until = future(3 * 24 * 3600)
      result = DeviceUpdateStatus.friendly_blocked_until(blocked_until)
      assert String.starts_with?(result, "until ")
    end
  end
end
