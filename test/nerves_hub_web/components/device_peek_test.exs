defmodule NervesHubWeb.Components.DevicePeekTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.FirmwareMetadata
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.DeploymentRelease
  alias NervesHubWeb.Components.DevicePeek

  defp device(attrs) do
    struct!(
      %Device{
        firmware_metadata: %FirmwareMetadata{uuid: "older", version: "2.3.2"},
        update_mode: :automatic,
        consecutive_failed_updates: 0,
        deployment_group: %DeploymentGroup{
          is_active: true,
          current_release: %DeploymentRelease{firmware: %Firmware{uuid: "release", version: "2.4.0"}}
        },
        latest_connection: %DeviceConnection{last_seen_at: DateTime.utc_now()}
      },
      attrs
    )
  end

  defp seen_days_ago(days), do: %DeviceConnection{last_seen_at: DateTime.add(DateTime.utc_now(), -days, :day)}

  describe "reason/3" do
    test "an update the device keeps failing comes first" do
      device =
        device(
          updates_blocked_until: DateTime.add(DateTime.utc_now(), 1, :hour),
          consecutive_failed_updates: 3,
          latest_health: %DeviceHealth{status: :unhealthy},
          latest_connection: seen_days_ago(20)
        )

      assert DevicePeek.reason(device, "offline", nil) == {:failing, "2.4.0", 3}
    end

    test "then its health, when it's warning or unhealthy" do
      health = %DeviceHealth{status: :warning}
      device = device(latest_health: health, latest_connection: seen_days_ago(20))

      assert DevicePeek.reason(device, "offline", nil) == {:health, health}
      assert DevicePeek.reason(device(latest_health: %DeviceHealth{status: :healthy}), "online", nil) == nil
    end

    test "then not being seen for 14 days or more" do
      assert {:not_seen, seconds} = DevicePeek.reason(device(latest_connection: seen_days_ago(20)), "offline", nil)
      assert div(seconds, 86_400) == 20

      assert DevicePeek.reason(device(latest_connection: seen_days_ago(3)), "offline", nil) == nil
    end

    test "then an update it is installing" do
      progress = %{stage: "downloading", percent: 40}
      device = device(inflight_update: %{firmware: %Firmware{version: "2.4.0"}})

      assert DevicePeek.reason(device, "online", progress) == {:updating, progress, "2.4.0"}
    end

    test "is nothing for a device with nothing wrong" do
      assert DevicePeek.reason(device([]), "online", nil) == nil
    end
  end
end
