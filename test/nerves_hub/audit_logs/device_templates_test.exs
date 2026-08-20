defmodule NervesHub.AuditLogs.DeviceTemplatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    Fixtures.standard_fixture(tmp_dir)
  end

  describe "device supplied failure reasons" do
    test "a long reason is truncated instead of overflowing the description", %{device: device} do
      # Devices report fwup stderr verbatim, which can run to any length.
      reason = String.duplicate("fwup: error writing to /dev/mmcblk0 at offset 12345678; ", 20)

      device = %{device | inflight_update: %{deployment_group: nil}}

      :ok = DeviceTemplates.audit_firmware_upgrade_failed(device, reason)

      [log] = AuditLogs.logs_for(device)

      assert log.description =~ "reported an error"
      assert log.description =~ "fwup: error writing"
      assert String.length(log.description) <= 500
      refute log.description =~ String.duplicate("fwup", 3)
    end

    test "a reason under the limit is kept whole", %{device: device} do
      reason = "fwup: partition table mismatch"

      device = %{device | inflight_update: %{deployment_group: nil}}

      :ok = DeviceTemplates.audit_firmware_upgrade_failed(device, reason)

      [log] = AuditLogs.logs_for(device)

      assert log.description =~ "(\"#{reason}\")"
    end

    test "a nil reason omits the reason clause entirely", %{device: device} do
      device = %{device | inflight_update: %{deployment_group: nil}}

      :ok = DeviceTemplates.audit_firmware_upgrade_failed(device, nil)

      [log] = AuditLogs.logs_for(device)

      assert log.description =~ "reported an error while trying to update its firmware"
      refute log.description =~ "("
    end

    test "long reasons are truncated for ignored upgrades too", %{device: device} do
      :ok = DeviceTemplates.audit_firmware_upgrade_ignored(device, nil, String.duplicate("b", 600))

      [log] = AuditLogs.logs_for(device)

      assert String.length(log.description) <= 500
    end

    test "long reasons are truncated for rescheduled upgrades too", %{device: device} do
      device = %{device | inflight_update: %{deployment_group: nil}}
      blocked_until = NaiveDateTime.utc_now() |> NaiveDateTime.add(60, :second)

      :ok =
        DeviceTemplates.audit_firmware_upgrade_rescheduled(
          device,
          blocked_until,
          String.duplicate("c", 600)
        )

      [log] = AuditLogs.logs_for(device)

      assert String.length(log.description) <= 500
    end
  end

  describe "long but legal column values" do
    test "a 255 character device identifier no longer overflows the description", %{
      device: device,
      user: user
    } do
      device = %{device | identifier: String.duplicate("d", 255)}

      :ok = DeviceTemplates.audit_reboot(user, device)

      [log] = AuditLogs.logs_for(device)

      assert log.description =~ "rebooted device"
    end
  end
end
