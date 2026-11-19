defmodule NervesHubWeb.Components.DeviceListTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHubWeb.Components.DeviceList

  @now ~U[2026-11-17 12:00:00Z]

  defp group(attrs \\ []) do
    struct!(
      %DeploymentGroup{
        is_active: true,
        current_release: %DeploymentRelease{firmware: %Firmware{uuid: "release", version: "2.4.0"}}
      },
      attrs
    )
  end

  defp device(attrs) do
    struct!(
      %Device{
        firmware_metadata: %FirmwareMetadata{uuid: "older", version: "2.3.2"},
        update_mode: :automatic,
        consecutive_failed_updates: 0,
        deployment_group: group()
      },
      attrs
    )
  end

  describe "update_state/3" do
    test "an update in progress comes first, with the firmware it installs" do
      device = device(inflight_update: %{firmware: %Firmware{version: "2.4.0"}})
      progress = %{stage: "downloading", percent: 43}

      assert DeviceList.update_state(device, progress, @now) == {:updating, progress, "2.4.0"}
    end

    test "a device running the release is up to date" do
      device = device(firmware_metadata: %FirmwareMetadata{uuid: "release", version: "2.4.0"})

      assert DeviceList.update_state(device, nil, @now) == :up_to_date
    end

    test "a device that can take the release is waiting for it" do
      assert DeviceList.update_state(device([]), nil, @now) == {:waiting, "2.4.0"}
    end

    test "a device blocked after failures is failing to take the release" do
      device = device(updates_blocked_until: DateTime.add(@now, 2, :hour), consecutive_failed_updates: 9)

      assert DeviceList.update_state(device, nil, @now) == {:failing, "2.4.0", 9}
    end

    test "a device blocked without a failure is in the penalty box" do
      until = DateTime.add(@now, 2, :hour)
      device = device(updates_blocked_until: until)

      assert DeviceList.update_state(device, nil, @now) == {:blocked, until}
    end

    test "says so when updates are off or the group is paused" do
      assert DeviceList.update_state(device(update_mode: :off), nil, @now) == :updates_off
      assert DeviceList.update_state(device(deployment_group: group(is_active: false)), nil, @now) == :group_paused
    end

    test "says nothing of a device in no group unless its updates are off" do
      assert DeviceList.update_state(device(deployment_group: nil), nil, @now) == nil
      assert DeviceList.update_state(device(deployment_group: nil, update_mode: :off), nil, @now) == :updates_off
    end

    test "says nothing of a device that hasn't reported its firmware" do
      assert DeviceList.update_state(device(firmware_metadata: nil), nil, @now) == nil
    end
  end

  describe "attention_reason/2" do
    defp failing(attrs \\ []) do
      device(
        [updates_blocked_until: DateTime.add(DateTime.utc_now(), 1, :hour), consecutive_failed_updates: 4] ++ attrs
      )
    end

    defp unhealthy(),
      do: %DeviceHealth{status: :unhealthy, status_reasons: %{"unhealthy" => %{"cpu_temp" => %{"value" => 82}}}}

    defp seen_days_ago(days), do: %DeviceConnection{last_seen_at: DateTime.add(DateTime.utc_now(), -days, :day)}

    test "says which update keeps failing" do
      assert DeviceList.attention_reason(failing()) == {:failing, "2.4.0", 4}
      assert DeviceList.attention_reason(failing(deployment_group: nil)) == {:failing, nil, 4}
    end

    test "says what made the device unhealthy" do
      assert DeviceList.attention_reason(device(latest_health: unhealthy())) == {:unhealthy, "temperature at 82 °C"}
    end

    test "says when the device was last seen, after 14 days" do
      seen = seen_days_ago(20)

      assert DeviceList.attention_reason(device(latest_connection: seen)) == {:not_seen, seen.last_seen_at}
      assert DeviceList.attention_reason(device(latest_connection: seen_days_ago(3))) == nil
    end

    test "has no time for a device that connected before connection records were kept" do
      assert DeviceList.attention_reason(device(status: :provisioned, latest_connection: nil)) == {:not_seen, nil}
      assert DeviceList.attention_reason(device(status: :registered, latest_connection: nil)) == nil
    end

    test "puts a failing update first, unless the list is filtered to another reason" do
      device = failing(latest_health: unhealthy(), latest_connection: seen_days_ago(20))

      assert {:failing, _, _} = DeviceList.attention_reason(device)
      assert {:unhealthy, _} = DeviceList.attention_reason(device, "unhealthy")
      assert {:not_seen, _} = DeviceList.attention_reason(device, "not_seen")
    end

    test "doesn't count a penalty box that has run out, or one with no failures behind it" do
      assert DeviceList.attention_reason(failing(updates_blocked_until: DateTime.add(DateTime.utc_now(), -1, :hour))) ==
               nil

      assert DeviceList.attention_reason(failing(consecutive_failed_updates: 0)) == nil
    end
  end

  describe "health_summary/1" do
    test "names the metric and its reading" do
      reasons = %{"unhealthy" => %{"mem_used_percent" => %{"value" => 94.4, "threshold" => 90}}}

      assert DeviceList.health_summary(%{status: :unhealthy, status_reasons: reasons}) == "memory at 94%"
    end

    test "names a share reason's threshold, since its value is a share of the window" do
      reasons = %{"warning" => %{"cpu_usage_percent" => %{"aggregation" => "share", "value" => 40, "threshold" => 80}}}

      assert DeviceList.health_summary(%{status: :warning, status_reasons: reasons}) == "CPU over 80%"
    end

    test "counts the other metrics" do
      reasons = %{"unhealthy" => %{"disk_used_percentage" => %{"value" => 97}, "load_15min" => %{"value" => 6}}}

      assert DeviceList.health_summary(%{status: :unhealthy, status_reasons: reasons}) == "disk at 97%, +1 more"
    end

    test "says so when the device gave no reason" do
      assert DeviceList.health_summary(%{status: :unhealthy, status_reasons: nil}) == "the device didn't say why"
    end
  end

  describe "state_tabs/1" do
    test "shows a placeholder for each count while new ones load" do
      tabs = Enum.map(DeviceList.tabs(), &Map.put(&1, :path, "/"))
      counts = %{"all" => 3, "online" => 1, "attention" => 0, "updating" => 0, "offline" => 2}

      html = render_component(&DeviceList.state_tabs/1, tabs: tabs, selected: "", counts: counts)
      refute html =~ "data-count-pending"

      html = render_component(&DeviceList.state_tabs/1, tabs: tabs, selected: "", counts: counts, loading: true)
      assert length(Regex.scan(~r/data-count-pending/, html)) == 5
    end
  end

  describe "no_matches/1" do
    test "offers the removals that would bring devices back, most first" do
      suggestions = [
        %{key: :tags, text: "tags: prod", count: 214},
        %{key: :platform, text: "platform: rpi4", count: 0},
        %{key: :advanced_query, text: "search", count: 6}
      ]

      html = render_component(&DeviceList.no_matches/1, removable: 3, suggestions: suggestions, can_reset: true)

      assert html =~ "No devices match these filters"
      assert html =~ ~s(id="no-matches-remove-tags")
      assert html =~ ~s(id="no-matches-remove-advanced_query")
      refute html =~ ~s(id="no-matches-remove-platform")
      assert html =~ "Clear filters"
    end

    test "says what one filter is hiding" do
      html =
        render_component(&DeviceList.no_matches/1,
          removable: 1,
          suggestions: [%{key: :tags, text: "tags: prod", count: 1}]
        )

      assert html =~ "No devices match this filter"
      assert html =~ "Without it, 1 device would show here."
    end

    test "waits for the counts before saying anything about them" do
      html = render_component(&DeviceList.no_matches/1, removable: 2, suggestions: nil)

      assert html =~ "No devices match both filters"
      refute html =~ "Removing one"
      refute html =~ "no-matches-remove"
    end
  end
end
