defmodule NervesHub.FirmwareUpdatesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(firmware, %{is_active: true, user: user})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    %{deployment_group: deployment_group, device: device}
  end

  describe "status_update/4 without an inflight update" do
    # A device can report a terminal update status with no inflight_updates row —
    # eg. a manual `fwup` run, or after the row expired. `fetch_device/2` builds a
    # placeholder for those, and its `deployment_group` association must not be
    # mistaken for a real deployment group.

    test "'failed' doesn't block the device and records a device scoped audit log", %{device: device} do
      assert :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})

      assert is_nil(Devices.get_device(device.id).updates_blocked_until)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, device)
      assert log.description =~ "reported an error (\"fwup error\") while trying to update its firmware."
      refute log.description =~ "Updates will be blocked"
    end

    test "'ignored' doesn't block the device and records a device scoped audit log", %{device: device} do
      assert :ok = FirmwareUpdates.status_update("ignored", device.id, %{"reason" => "busy"})

      assert is_nil(Devices.get_device(device.id).updates_blocked_until)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, device)
      assert log.description =~ "ignored the manual firmware upgrade request because of \"busy\""
    end

    test "'rescheduled' doesn't block the device and records a device scoped audit log", %{device: device} do
      info = %{"delay_for" => 60_000, "reason" => "on battery"}

      assert :ok = FirmwareUpdates.status_update("rescheduled", device.id, info)

      assert is_nil(Devices.get_device(device.id).updates_blocked_until)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, device)
      assert log.description =~ "During a manual firmware update request"
      assert log.description =~ "on battery"
    end
  end

  describe "status_update/4 with a deployment group inflight update" do
    setup %{deployment_group: deployment_group, device: device} do
      deployment_group = ManagedDeployments.load_current_release(deployment_group)

      {:ok, _inflight_update} =
        InflightUpdate.deployment_requested_changeset(deployment_group, device.id, false)
        |> Repo.insert()

      %{deployment_group: deployment_group}
    end

    test "'failed' blocks the device for the penalty timeout", %{
      deployment_group: deployment_group,
      device: device
    } do
      assert :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})

      assert blocked_until = Devices.get_device(device.id).updates_blocked_until
      assert_blocked_for(blocked_until, deployment_group.penalty_timeout_minutes)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, deployment_group)
      assert log.description =~ "Updates will be blocked for #{deployment_group.penalty_timeout_minutes} minutes"
    end

    test "'ignored' blocks the device for the penalty timeout", %{
      deployment_group: deployment_group,
      device: device
    } do
      assert :ok = FirmwareUpdates.status_update("ignored", device.id, %{"reason" => "busy"})

      assert blocked_until = Devices.get_device(device.id).updates_blocked_until
      assert_blocked_for(blocked_until, deployment_group.penalty_timeout_minutes)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, deployment_group)
      assert log.description =~ "ignored the scheduled firmware upgrade request"
    end

    test "'rescheduled' blocks the device until the requested time", %{
      deployment_group: deployment_group,
      device: device
    } do
      info = %{"delay_for" => 60_000, "reason" => "on battery"}

      assert :ok = FirmwareUpdates.status_update("rescheduled", device.id, info)

      assert blocked_until = Devices.get_device(device.id).updates_blocked_until
      assert_blocked_for(blocked_until, 1)

      assert [log] = AuditLogs.logs_for(device)
      assert_actor(log, deployment_group)
      assert log.description =~ "During an update request from \"#{deployment_group.name}\""
    end
  end

  defp assert_actor(log, %type{id: id}) do
    assert log.actor_type == type
    assert log.actor_id == id
  end

  defp assert_blocked_for(blocked_until, minutes) do
    expected = DateTime.utc_now() |> DateTime.add(minutes, :minute)

    assert_in_delta DateTime.to_unix(blocked_until), DateTime.to_unix(expected), 5
  end
end
