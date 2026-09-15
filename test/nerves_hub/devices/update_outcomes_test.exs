defmodule NervesHub.Devices.UpdateOutcomesTest do
  @moduledoc """
  Every way a firmware update can end, and what each does to the device's
  consecutive failure count.

  Asserts on the PostgreSQL half of the pair only, which is the exact one —
  `NervesHub.Devices.UpdateHistoryTest` covers the ClickHouse rows, and has to
  be non-async to do it.
  """

  use NervesHub.DataCase, async: true

  alias NervesHub.Devices
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0", dir: tmp_dir})
    deployment_group = Fixtures.deployment_group_fixture(target_firmware, %{is_active: true, user: user})
    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

    %{
      user: user,
      org: org,
      product: product,
      firmware: firmware,
      target_firmware: target_firmware,
      deployment_group: deployment_group,
      device: device
    }
  end

  defp request_update(deployment_group, device) do
    {:ok, inflight_update} =
      deployment_group
      |> InflightUpdate.deployment_requested_changeset(device.id, false)
      |> Repo.insert()

    inflight_update
  end

  defp failure_count(device), do: Devices.get_device(device.id).consecutive_failed_updates

  describe "a device that reports how its update went" do
    test "'failed' counts against it", %{device: device, deployment_group: deployment_group} do
      _ = request_update(deployment_group, device)

      assert :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})

      assert failure_count(device) == 1
      refute is_nil(Devices.get_device(device.id).last_update_failure_at)
    end

    test "'ignored' counts against it", %{device: device, deployment_group: deployment_group} do
      _ = request_update(deployment_group, device)

      assert :ok = FirmwareUpdates.status_update("ignored", device.id, %{"reason" => "busy"})

      assert failure_count(device) == 1
    end

    test "'rescheduled' does not, because asking for it later is not failing", %{
      device: device,
      deployment_group: deployment_group
    } do
      _ = request_update(deployment_group, device)

      assert :ok =
               FirmwareUpdates.status_update("rescheduled", device.id, %{
                 "delay_for" => 60_000,
                 "reason" => "recording"
               })

      assert failure_count(device) == 0
      assert is_nil(Devices.get_device(device.id).last_update_failure_at)
    end

    test "each failure adds to the last, so a device stuck in the loop climbs", %{
      device: device,
      deployment_group: deployment_group
    } do
      for _ <- 1..3 do
        _ = request_update(deployment_group, device)
        :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})
      end

      assert failure_count(device) == 3
    end
  end

  describe "a device that says nothing at all" do
    test "an update that stops making progress counts against it once it expires", %{
      device: device,
      deployment_group: deployment_group
    } do
      inflight_update = request_update(deployment_group, device)

      # `updated_at` is a NaiveDateTime, and the expiry worker compares it
      # against the database's `NOW()`.
      stale = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -31, :minute)

      InflightUpdate
      |> where(id: ^inflight_update.id)
      |> Repo.update_all(set: [updated_at: stale])

      assert FirmwareUpdates.delete_expired_inflight_updates() == 1

      assert failure_count(device) == 1
    end

    test "rejoining still on its old firmware counts against it", %{
      device: device,
      deployment_group: deployment_group
    } do
      _ = request_update(deployment_group, device)

      assert :ok = FirmwareUpdates.abandon_inflight_update(device)

      assert failure_count(device) == 1
      assert is_nil(FirmwareUpdates.inflight_update_for(device))
    end

    test "rejoining with nothing inflight is not a failure", %{device: device} do
      assert :ok = FirmwareUpdates.abandon_inflight_update(device)

      assert failure_count(device) == 0
    end
  end

  describe "a device that takes its firmware" do
    test "clears the run of failures", %{
      device: device,
      deployment_group: deployment_group,
      firmware: firmware,
      target_firmware: target_firmware
    } do
      _ = request_update(deployment_group, device)
      :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})

      _ = request_update(deployment_group, device)
      :ok = FirmwareUpdates.status_update("failed", device.id, %{"reason" => "fwup error"})

      assert failure_count(device) == 2

      {:ok, source_metadata} = Firmwares.metadata_from_firmware(firmware)
      {:ok, target_metadata} = Firmwares.metadata_from_firmware(target_firmware)

      {:ok, device} = Devices.update_firmware_metadata(device, target_metadata, :unknown, false)
      _ = request_update(deployment_group, device)

      assert {:ok, _device} = FirmwareUpdates.firmware_update_successful(device, source_metadata)

      assert failure_count(device) == 0
      assert is_nil(Devices.get_device(device.id).last_update_failure_at)
    end
  end
end
