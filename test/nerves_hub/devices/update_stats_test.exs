defmodule NervesHub.Devices.UpdateStatsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Devices.UpdateStats
  alias NervesHub.Firmwares.FirmwareDelta
  alias NervesHub.Fixtures
  alias NervesHub.AnalyticsRepo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    firmware2 = Fixtures.firmware_fixture(org_key, product, %{version: "2.0.0"})

    deployment_group = Fixtures.deployment_group_fixture(org, firmware, %{is_active: true})

    deployment_group2 =
      Fixtures.deployment_group_fixture(org, firmware2, %{
        is_active: true,
        name: "test-deployment-2"
      })

    device = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})
    device2 = Fixtures.device_fixture(org, product, firmware)
    device3 = Fixtures.device_fixture(org, product, firmware)

    # Create a second product for cross-product testing
    product2 = Fixtures.product_fixture(user, org, %{name: "test-product-2"})
    device4 = Fixtures.device_fixture(org, product2, firmware)

    # Create firmware delta for testing delta updates
    firmware_delta = Fixtures.firmware_delta_fixture(firmware, firmware2)

    AnalyticsRepo.query("TRUNCATE TABLE update_stats", [])

    {:ok,
     %{
       device: device,
       device2: device2,
       device3: device3,
       device4: device4,
       product: product,
       product2: product2,
       deployment_group: deployment_group,
       deployment_group2: deployment_group2,
       firmware: firmware,
       firmware2: firmware2,
       firmware_delta: firmware_delta
     }}
  end

  describe "log_full_update/2" do
    test "creates update stat record for full update", %{
      device: device,
      deployment_group: deployment_group
    } do
      assert :ok =
               UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      stats = AnalyticsRepo.all(UpdateStat)
      assert length(stats) == 1

      [stat] = stats
      assert stat.device_id == device.id
      assert stat.product_id == device.product_id
      assert stat.deployment_id == deployment_group.id
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
      assert stat.update_bytes == deployment_group.firmware.size
      assert stat.saved_bytes == 0
      assert stat.type == "fwup_full"
    end

    test "creates record with source firmware uuid when device has firmware metadata", %{
      deployment_group: deployment_group,
      firmware: firmware
    } do
      device_with_metadata = %Device{
        id: 123,
        product_id: 456,
        firmware_metadata: %{uuid: firmware.uuid}
      }

      assert :ok =
               UpdateStats.log_full_update(
                 device_with_metadata,
                 deployment_group,
                 deployment_group.firmware
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.source_firmware_uuid == firmware.uuid
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
    end

    test "creates record with nil source firmware uuid when device has no metadata", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Remove firmware_metadata from device
      device_without_metadata = Map.delete(device, :firmware_metadata)

      assert :ok =
               UpdateStats.log_full_update(
                 device_without_metadata,
                 deployment_group,
                 deployment_group.firmware
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.source_firmware_uuid == nil
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
    end
  end

  describe "log_delta_update/3" do
    test "creates update stat record for delta update", %{
      device: device,
      deployment_group: deployment_group,
      firmware_delta: firmware_delta
    } do
      assert :ok =
               UpdateStats.log_delta_update(
                 device,
                 deployment_group,
                 deployment_group.firmware,
                 firmware_delta
               )

      stats = AnalyticsRepo.all(UpdateStat)
      assert length(stats) == 1

      [stat] = stats
      assert stat.device_id == device.id
      assert stat.product_id == device.product_id
      assert stat.deployment_id == deployment_group.id
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
      assert stat.type == "fwup_delta"

      expected_saved = deployment_group.firmware.size - firmware_delta.size

      assert stat.update_bytes == firmware_delta.size
      assert stat.saved_bytes == expected_saved
    end

    test "handles firmware delta without size metadata", %{
      device: device,
      deployment_group: deployment_group,
      firmware_delta: firmware_delta
    } do
      # Create firmware delta without size in metadata
      firmware_delta_no_size = %FirmwareDelta{firmware_delta | size: 0}

      assert :ok =
               UpdateStats.log_delta_update(
                 device,
                 deployment_group,
                 deployment_group.firmware,
                 firmware_delta_no_size
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      # Should fall back to target firmware size
      assert stat.update_bytes == deployment_group.firmware.size
      assert stat.saved_bytes == 0
    end

    test "creates record with source firmware uuid when device has firmware metadata", %{
      deployment_group: deployment_group,
      firmware: firmware,
      firmware_delta: firmware_delta
    } do
      device_with_metadata = %Device{
        id: 123,
        product_id: 456,
        firmware_metadata: %{uuid: firmware.uuid}
      }

      assert :ok =
               UpdateStats.log_delta_update(
                 device_with_metadata,
                 deployment_group,
                 deployment_group.firmware,
                 firmware_delta
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.source_firmware_uuid == firmware.uuid
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
    end
  end

  describe "stats_by_device/1" do
    test "returns aggregated stats for a specific device", %{
      device: device,
      device2: device2,
      deployment_group: deployment_group,
      firmware_delta: firmware_delta
    } do
      # Create stats for device
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      UpdateStats.log_delta_update(
        device,
        deployment_group,
        deployment_group.firmware,
        firmware_delta
      )

      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      # Create stats for device2 (should not be included)
      UpdateStats.log_full_update(device2, deployment_group, deployment_group.firmware)

      result = UpdateStats.stats_by_device(device)

      # Should aggregate all updates for this device
      expected_bytes = deployment_group.firmware.size * 2 + firmware_delta.size

      assert result.total_update_bytes == expected_bytes
      assert result.num_updates == 3
      assert is_integer(result.total_saved_bytes)
    end

    test "returns empty result for device with no stats", %{device: device} do
      result = UpdateStats.stats_by_device(device)
      assert result == %{total_update_bytes: 0, num_updates: 0, total_saved_bytes: 0}
    end

    test "handles device with only one stat record", %{
      device: device,
      deployment_group: deployment_group
    } do
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

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
      firmware: firmware,
      firmware2: firmware2,
      firmware_delta: firmware_delta
    } do
      # Device with firmware metadata (source uuid = firmware.uuid)
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}
      UpdateStats.log_full_update(device_with_metadata, deployment_group, firmware)

      UpdateStats.log_delta_update(
        device_with_metadata,
        deployment_group,
        deployment_group.firmware,
        firmware_delta
      )

      # Device with different firmware metadata (source uuid = firmware2.uuid)
      device_with_metadata2 = %{device2 | firmware_metadata: %{uuid: firmware2.uuid}}

      UpdateStats.log_full_update(
        device_with_metadata2,
        deployment_group,
        deployment_group.firmware
      )

      stats = UpdateStats.stats_by_deployment(deployment_group)

      # Results should be grouped by source_firmware_uuid
      assert stats[firmware.uuid].num_updates == 2
      assert stats[firmware2.uuid].num_updates == 1
    end

    test "returns empty result for deployment with no stats", %{
      deployment_group: deployment_group
    } do
      result = UpdateStats.stats_by_deployment(deployment_group)
      assert result == %{}
    end

    test "filters by deployment_id and target_firmware_uuid", %{
      device: device,
      deployment_group: deployment_group,
      deployment_group2: deployment_group2,
      firmware: firmware
    } do
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}

      # Stats for deployment_group
      UpdateStats.log_full_update(
        device_with_metadata,
        deployment_group,
        deployment_group.firmware
      )

      # Stats for deployment_group2 (should not be included)
      UpdateStats.log_full_update(
        device_with_metadata,
        deployment_group2,
        deployment_group2.firmware
      )

      results = UpdateStats.stats_by_deployment(deployment_group)
      assert Enum.count(results) == 1
      source_firmware_uuid = firmware.uuid
      %{^source_firmware_uuid => result} = results

      assert result.total_update_bytes == deployment_group.firmware.size
      assert result.total_saved_bytes == 0
      assert result.num_updates == 1
    end
  end

  describe "total_stats_by_product/1" do
    test "returns aggregated stats for all devices in a product", %{
      device: device,
      device2: device2,
      device4: device4,
      product: product,
      deployment_group: deployment_group,
      firmware_delta: firmware_delta
    } do
      # Stats for devices in product
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      UpdateStats.log_delta_update(
        device2,
        deployment_group,
        deployment_group.firmware,
        firmware_delta
      )

      # Stats for device in product2 (should not be included)
      UpdateStats.log_full_update(device4, deployment_group, deployment_group.firmware)

      result = UpdateStats.total_stats_by_product(product)

      expected_bytes =
        deployment_group.firmware.size + firmware_delta.size

      assert result.total_update_bytes == expected_bytes
      assert result.num_updates == 2
      assert is_integer(result.total_saved_bytes)
    end

    test "returns empty result for product with no stats", %{product: product} do
      result = UpdateStats.total_stats_by_product(product)
      assert result == %{total_update_bytes: 0, num_updates: 0, total_saved_bytes: 0}
    end

    test "handles product with multiple update types", %{
      device: device,
      product: product,
      deployment_group: deployment_group,
      firmware_delta: firmware_delta
    } do
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      UpdateStats.log_delta_update(
        device,
        deployment_group,
        deployment_group.firmware,
        firmware_delta
      )

      result = UpdateStats.total_stats_by_product(product)

      expected_bytes = deployment_group.firmware.size + firmware_delta.size

      assert result.total_update_bytes == expected_bytes
      assert result.num_updates == 2
      assert is_integer(result.total_saved_bytes)
    end
  end

  describe "integration tests" do
    test "multiple devices and deployments with various stats", %{
      device: device,
      device2: device2,
      device3: device3,
      product: product,
      deployment_group: deployment_group,
      deployment_group2: deployment_group2,
      firmware: firmware,
      firmware_delta: firmware_delta
    } do
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}
      device2_with_metadata = %{device2 | firmware_metadata: %{uuid: firmware.uuid}}

      # Multiple stats for different scenarios
      UpdateStats.log_full_update(
        device_with_metadata,
        deployment_group,
        deployment_group.firmware
      )

      UpdateStats.log_delta_update(
        device_with_metadata,
        deployment_group,
        deployment_group.firmware,
        firmware_delta
      )

      UpdateStats.log_full_update(
        device2_with_metadata,
        deployment_group,
        deployment_group.firmware
      )

      UpdateStats.log_full_update(device3, deployment_group2, deployment_group2.firmware)

      # Test stats_by_device
      device_stats = UpdateStats.stats_by_device(device)
      assert device_stats.num_updates == 2
      assert is_integer(device_stats.total_update_bytes)
      assert is_integer(device_stats.total_saved_bytes)

      source_firmware_uuid = firmware.uuid
      # Test stats_by_deployment
      %{^source_firmware_uuid => stat} = UpdateStats.stats_by_deployment(deployment_group)
      assert stat.num_updates == 3
      assert is_integer(stat.total_update_bytes)
      assert is_integer(stat.total_saved_bytes)

      # Test total_stats_by_product
      product_stats = UpdateStats.total_stats_by_product(product)
      # All updates for this product (3 from deployment_group + 1 from deployment_group2)
      assert product_stats.num_updates == 4
      assert is_integer(product_stats.total_update_bytes)
      assert is_integer(product_stats.total_saved_bytes)
    end
  end

  describe "edge cases" do
    test "handles firmware delta with very large size", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Create firmware delta with large size in metadata
      large_firmware_delta = %FirmwareDelta{
        size: 1_000_000_000
      }

      assert :ok =
               UpdateStats.log_delta_update(
                 device,
                 deployment_group,
                 deployment_group.firmware,
                 large_firmware_delta
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.update_bytes == 1_000_000_000
      # Saved bytes could be negative if delta is larger than target
      expected_saved = deployment_group.firmware.size - 1_000_000_000
      assert stat.saved_bytes == expected_saved
    end

    test "handles multiple full updates for same device and deployment", %{
      device: device,
      deployment_group: deployment_group
    } do
      # Log multiple full updates
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)
      UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)

      result = UpdateStats.stats_by_device(device)
      assert result.num_updates == 3
      assert result.total_update_bytes == deployment_group.firmware.size * 3
      assert result.total_saved_bytes == 0
    end
  end

  test "performance with many stats", %{
    device: device,
    deployment_group: deployment_group,
    firmware_delta: firmware_delta
  } do
    # Create many stats to test performance
    for i <- 1..25 do
      if rem(i, 2) == 0 do
        UpdateStats.log_full_update(device, deployment_group, deployment_group.firmware)
      else
        UpdateStats.log_delta_update(
          device,
          deployment_group,
          deployment_group.firmware,
          firmware_delta
        )
      end
    end

    result = UpdateStats.stats_by_device(device)
    assert result.num_updates == 25
    assert is_integer(result.total_update_bytes)
    assert is_integer(result.total_saved_bytes)
  end
end
