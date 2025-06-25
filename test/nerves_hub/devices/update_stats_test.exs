defmodule NervesHub.Devices.UpdateStatsTest do
  alias NervesHub.ManagedDeployments
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    source_firmware = Fixtures.firmware_fixture(org_key, product)
    target_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})
    other_firmware = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.1"})

    deployment_group = Fixtures.deployment_group_fixture(org, target_firmware, %{is_active: true})

    device = Fixtures.device_fixture(org, product, source_firmware, %{status: :provisioned})

    # Ensure device firmware metadata reflects the target firmware because
    # update stats are logged after a successful firmware update
    {:ok, metadata} = Firmwares.metadata_from_firmware(target_firmware)

    {:ok, device} =
      Devices.update_firmware_metadata(device, metadata)

    device2 = Fixtures.device_fixture(org, product, target_firmware)
    device3 = Fixtures.device_fixture(org, product, target_firmware)

    {:ok, source_firmware_metadata} = Firmwares.metadata_from_firmware(source_firmware)

    {:ok,
     %{
       user: user,
       org: org,
       device: device,
       device2: device2,
       device3: device3,
       product: product,
       deployment_group: deployment_group,
       source_firmware: source_firmware,
       target_firmware: target_firmware,
       other_firmware: other_firmware,
       source_firmware_metadata: source_firmware_metadata
     }}
  end

  describe "log_update/2" do
    test "creates update stat record for full update", %{
      device: device,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      deployment_group: deployment_group
    } do
      {:ok, metadata} = Firmwares.metadata_from_firmware(source_firmware)
      device = Devices.update_deployment_group(device, deployment_group)
      assert :ok = UpdateStats.log_update(device, metadata)

      stats = Repo.all(UpdateStat)
      assert length(stats) == 1

      [stat] = stats
      assert stat.device_id == device.id
      assert stat.product_id == device.product_id
      assert stat.deployment_id == deployment_group.id
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
      assert stat.target_firmware_uuid == target_firmware.uuid
      assert stat.update_bytes == deployment_group.firmware.size
      assert stat.saved_bytes == 0
      assert stat.type == "fwup_full"
    end

    test "creates update stat record for a delta update", %{
      device: device,
      source_firmware: source_firmware,
      target_firmware: target_firmware
    } do
      {:ok, metadata} = Firmwares.metadata_from_firmware(source_firmware)
      delta = Fixtures.firmware_delta_fixture(source_firmware, target_firmware)
      assert :ok = UpdateStats.log_update(device, metadata)

      stats = Repo.all(UpdateStat)
      assert length(stats) == 1

      [stat] = stats
      assert stat.device_id == device.id
      assert stat.product_id == device.product_id
      assert stat.target_firmware_uuid == target_firmware.uuid
      assert stat.update_bytes == delta.size
      assert stat.saved_bytes == target_firmware.size - delta.size
      assert stat.type == "fwup_delta"
    end

    test "deployment group isn't set when device has no deployment group", %{
      device: device,
      source_firmware: source_firmware
    } do
      {:ok, metadata} = Firmwares.metadata_from_firmware(source_firmware)
      assert :ok = UpdateStats.log_update(device, metadata)

      [stat] = Repo.all(UpdateStat)

      refute stat.deployment_id
    end

    test "deployment group isn't set if target firmware doesn't match deployment's firmware", %{
      device: device,
      deployment_group: deployment_group,
      other_firmware: other_firmware
    } do
      device = Devices.update_deployment_group(device, deployment_group)
      assert device.deployment_id

      {:ok, metadata} = Firmwares.metadata_from_firmware(other_firmware)

      {:ok, device} =
        Devices.update_firmware_metadata(device, metadata)

      assert :ok = UpdateStats.log_update(device, nil)

      [stat] = Repo.all(UpdateStat)

      refute stat.deployment_id
    end
  end

  describe "stats_by_device/1" do
    test "returns aggregated stats for a specific device", %{
      device: device,
      device2: device2,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      source_firmware_metadata: source_firmware_metadata
    } do
      :ok = UpdateStats.log_update(device, source_firmware_metadata)
      delta = Fixtures.firmware_delta_fixture(source_firmware, target_firmware)
      :ok = UpdateStats.log_update(device, source_firmware_metadata)

      # Create stats for device2 (should not be included)
      UpdateStats.log_update(device2, source_firmware_metadata)

      result = UpdateStats.stats_by_device(device)

      # Should aggregate all updates for this device
      expected_bytes = deployment_group.firmware.size + delta.size

      assert result.total_update_bytes == expected_bytes
      assert result.num_updates == 2
      assert is_integer(result.total_saved_bytes)
    end

    test "returns empty result for device with no stats", %{device: device} do
      result = UpdateStats.stats_by_device(device)
      assert result == %{total_update_bytes: 0, num_updates: 0, total_saved_bytes: 0}
    end

    test "handles device with only one stat record", %{
      device: device,
      source_firmware_metadata: source_firmware_metadata,
      deployment_group: deployment_group
    } do
      UpdateStats.log_update(device, source_firmware_metadata)

      result = UpdateStats.stats_by_device(device)

      assert result.total_update_bytes == deployment_group.firmware.size
      assert result.total_saved_bytes == 0
      assert result.num_updates == 1
    end
  end

  describe "stats_by_deployment/1" do
    test "returns stats grouped by source firmware uuid for deployment", %{
      device: device,
      device2: device2,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      other_firmware: other_firmware,
      source_firmware_metadata: source_firmware_metadata
    } do
      device = Devices.update_deployment_group(device, deployment_group)
      device2 = Devices.update_deployment_group(device2, deployment_group)

      :ok = UpdateStats.log_update(device, source_firmware_metadata)
      _ = Fixtures.firmware_delta_fixture(source_firmware, target_firmware)
      :ok = UpdateStats.log_update(device, source_firmware_metadata)

      {:ok, deployment_group} =
        ManagedDeployments.update_deployment_group(deployment_group, %{
          firmware_id: other_firmware.id
        })

      # deployment group needs to be explicitly passed in because association
      # is already preloaded from fixtures, causing the preload in log_update/2
      # to noop
      :ok =
        UpdateStats.log_update(
          %{
            device2
            | firmware_metadata: %{uuid: other_firmware.uuid},
              deployment_group: deployment_group
          },
          source_firmware_metadata
        )

      stats = UpdateStats.stats_by_deployment(deployment_group)

      assert stats[target_firmware.uuid].num_updates == 2
      assert stats[other_firmware.uuid].num_updates == 1
    end

    test "returns empty result for deployment with no stats", %{
      deployment_group: deployment_group
    } do
      result = UpdateStats.stats_by_deployment(deployment_group)
      assert result == %{}
    end
  end

  describe "total_stats_by_product/1" do
    test "returns aggregated stats for all devices in a product", %{
      user: user,
      org: org,
      device: device,
      device2: device2,
      product: product,
      deployment_group: deployment_group,
      source_firmware: source_firmware,
      target_firmware: target_firmware,
      source_firmware_metadata: source_firmware_metadata
    } do
      # Stats for devices in product
      :ok = UpdateStats.log_update(device, source_firmware_metadata)
      delta = Fixtures.firmware_delta_fixture(source_firmware, target_firmware)
      :ok = UpdateStats.log_update(device2, source_firmware_metadata)

      product2 = Fixtures.product_fixture(user, org, %{name: "test-product-2"})
      device3 = Fixtures.device_fixture(org, product2, source_firmware)

      # Stats for device in product2 (should not be included)
      :ok = UpdateStats.log_update(device3, source_firmware_metadata)

      result = UpdateStats.total_stats_by_product(product)

      expected_bytes =
        deployment_group.firmware.size + delta.size

      assert result.total_update_bytes == expected_bytes
      assert result.num_updates == 2
      assert is_integer(result.total_saved_bytes)
    end

    test "returns empty result for product with no stats", %{product: product} do
      result = UpdateStats.total_stats_by_product(product)
      assert result == %{total_update_bytes: 0, num_updates: 0, total_saved_bytes: 0}
    end
  end
end
