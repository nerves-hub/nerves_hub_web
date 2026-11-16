defmodule NervesHub.AuditLogs.DeviceTemplatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Archives.Archive
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.SharedSecretAuth
  alias NervesHub.Devices.Updates
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

  describe "kinds" do
    # Each entry a device's Activity tab shows says what kind of event it is,
    # which is what the tab draws its icon from.
    test "every device template records its kind", %{
      device: device,
      user: user,
      firmware: firmware,
      deployment_group: deployment_group
    } do
      in_deployment = %{device | inflight_update: %{deployment_group: deployment_group}}
      manual = %{device | inflight_update: %{deployment_group: nil}}
      auth = %SharedSecretAuth{key: "nhp_key"}
      later = NaiveDateTime.add(NaiveDateTime.utc_now(), 3600)

      cases = [
        {:device_rebooted, fn -> DeviceTemplates.audit_reboot(user, device) end},
        {:reconnect_requested, fn -> DeviceTemplates.audit_request_action(user, device, :reconnect) end},
        {:identify_requested, fn -> DeviceTemplates.audit_request_action(user, device, :identify, "Slack") end},
        {:script_run, fn -> DeviceTemplates.audit_script_run(user, device, "uptime") end},
        {:shared_secret_created, fn -> DeviceTemplates.audit_shared_secret_created(user, device, auth) end},
        {:shared_secret_deactivated, fn -> DeviceTemplates.audit_shared_secret_deactivated(user, device, auth) end},
        {:update_attempted, fn -> {:ok, _} = DeviceTemplates.audit_update_attempt(device) end},
        {:firmware_pushed, fn -> DeviceTemplates.audit_pushed_available_update(user, device, firmware) end},
        {:firmware_pushed, fn -> DeviceTemplates.audit_firmware_pushed(user, device, firmware) end},
        {:firmware_metadata_updated, fn -> DeviceTemplates.audit_firmware_metadata_updated(device) end},
        {:firmware_validated, fn -> DeviceTemplates.audit_firmware_validated(device) end},
        {:update_ignored, fn -> DeviceTemplates.audit_firmware_upgrade_ignored(device, deployment_group, nil) end},
        {:update_ignored, fn -> DeviceTemplates.audit_firmware_upgrade_ignored(device, nil, nil) end},
        {:updates_blocked,
         fn -> DeviceTemplates.audit_firmware_upgrade_blocked(deployment_group, device, firmware) end},
        {:update_rescheduled, fn -> DeviceTemplates.audit_firmware_upgrade_rescheduled(in_deployment, later, nil) end},
        {:update_rescheduled, fn -> DeviceTemplates.audit_firmware_upgrade_rescheduled(manual, later, nil) end},
        {:update_failed, fn -> DeviceTemplates.audit_firmware_upgrade_failed(in_deployment, nil) end},
        {:update_failed, fn -> DeviceTemplates.audit_firmware_upgrade_failed(manual, nil) end},
        {:firmware_updated, fn -> DeviceTemplates.audit_firmware_updated(device) end},
        {:deployment_update_sent,
         fn -> DeviceTemplates.audit_device_deployment_group_update_triggered(device, deployment_group, firmware) end},
        {:update_requested,
         fn -> DeviceTemplates.audit_device_requested_update(device, deployment_group, firmware) end},
        {:deployment_group_set,
         fn -> DeviceTemplates.audit_device_deployment_group_update(user, device, deployment_group) end},
        {:deployment_group_set, fn -> DeviceTemplates.audit_set_deployment(device, deployment_group, :one_found) end},
        {:deployment_group_set,
         fn -> DeviceTemplates.audit_set_deployment(device, deployment_group, :multiple_found) end},
        {:archive_sent,
         fn ->
           DeviceTemplates.audit_device_archive_update_triggered(
             device,
             %Archive{uuid: Ecto.UUID.generate()},
             Ecto.UUID.generate()
           )
         end}
      ]

      for {kind, write} <- cases do
        write.()
        assert [%{kind: ^kind} | _] = AuditLogs.logs_for(device), "expected #{kind}"
      end
    end

    test "a device falling out of its deployment group records its kind", %{
      device: device,
      deployment_group: deployment_group
    } do
      :ok = DeploymentGroupTemplates.audit_deployment_mismatch(device, deployment_group, "tags")

      assert [%{kind: :deployment_group_mismatch}] = AuditLogs.logs_by(device)
    end

    test "changes made to a device record their kind", %{device: device, user: user, org: org} do
      cases = [
        {:tags_changed, fn -> Devices.tag_device(device, user, ["a"]) end},
        {:tags_changed, fn -> Devices.add_tags(device, user, ["b"]) end},
        {:tags_changed, fn -> Devices.remove_tags(device, user, ["a"]) end},
        {:device_updated, fn -> Devices.update_device_settings(device, %{description: "lab"}, user) end},
        {:updates_disabled, fn -> Updates.disable_updates(device, user) end},
        {:updates_enabled, fn -> Updates.enable_updates(device, user) end},
        {:updates_disabled, fn -> Updates.pause_automatic_updates(%{device | update_mode: :automatic}, user) end},
        {:update_mode_changed, fn -> Updates.set_update_mode(device, :off, user) end},
        {:update_mode_changed, fn -> Updates.revert_unsupported_update_mode(device) end},
        {:managed_updates_changed, fn -> Updates.set_managed_updates_allowed(device, true, user) end},
        {:penalty_box_cleared, fn -> Updates.clear_penalty_box(device, user) end}
      ]

      for {kind, change} <- cases do
        {:ok, _} = change.()
        assert [%{kind: ^kind} | _] = AuditLogs.logs_for(device), "expected #{kind}"
      end

      product = Fixtures.product_fixture(user, org, %{name: "Elsewhere"})
      {:ok, moved} = Devices.move(device, product, user)

      assert [%{kind: :device_moved} | _] = AuditLogs.logs_for(moved)
    end
  end
end
