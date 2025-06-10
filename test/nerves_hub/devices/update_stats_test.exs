defmodule NervesHub.Devices.UpdateStatsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.UpdateStat
  alias NervesHub.Devices.UpdateStats
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
       firmware2: firmware2
     }}
  end

  describe "log_stat/4" do
    test "creates update stat record successfully", %{
      device: device,
      deployment_group: deployment_group
    } do
      update_bytes = 1024
      saved_bytes = 256

      assert :ok =
               UpdateStats.log_stat(
                 device,
                 deployment_group,
                 :fwup_full,
                 update_bytes,
                 saved_bytes
               )

      stats = AnalyticsRepo.all(UpdateStat)
      assert length(stats) == 1

      [stat] = stats
      assert stat.device_id == device.id
      assert stat.product_id == device.product_id
      assert stat.deployment_id == deployment_group.id
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
      assert stat.update_bytes == update_bytes
      assert stat.saved_bytes == saved_bytes
    end

    test "creates record with source firmware uuid when device has firmware metadata", %{
      deployment_group: deployment_group,
      firmware: firmware
    } do
      device_with_metadata = %{
        id: 123,
        product_id: 456,
        firmware_metadata: %{uuid: firmware.uuid}
      }

      assert :ok =
               UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_full, 1024, 256)

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
               UpdateStats.log_stat(
                 device_without_metadata,
                 deployment_group,
                 :fwup_full,
                 1024,
                 256
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.source_firmware_uuid == nil
      assert stat.target_firmware_uuid == deployment_group.firmware.uuid
    end

    test "defaults saved_bytes to 0 when not provided", %{
      device: device,
      deployment_group: deployment_group
    } do
      update_bytes = 1024

      assert :ok = UpdateStats.log_stat(device, deployment_group, :fwup_full, update_bytes)

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.update_bytes == update_bytes
      assert stat.saved_bytes == 0
    end

    test "handles negative saved_bytes", %{
      device: device,
      deployment_group: deployment_group
    } do
      update_bytes = 1024
      saved_bytes = -128

      assert :ok =
               UpdateStats.log_stat(
                 device,
                 deployment_group,
                 :fwup_full,
                 update_bytes,
                 saved_bytes
               )

      [stat] = AnalyticsRepo.all(UpdateStat)
      assert stat.update_bytes == update_bytes
      assert stat.saved_bytes == saved_bytes
    end
  end

  describe "stats_by_device/1" do
    test "returns aggregated stats for a specific device", %{
      device: device,
      device2: device2,
      deployment_group: deployment_group
    } do
      # Create stats for device
      UpdateStats.log_stat(device, deployment_group, :fwup_full, 1000, 100)
      UpdateStats.log_stat(device, deployment_group, :fwup_delta, 2000, 200)
      UpdateStats.log_stat(device, deployment_group, :fwup_full, 1500, 150)

      # Create stats for device2 (should not be included)
      UpdateStats.log_stat(device2, deployment_group, :fwup_full, 500, 50)

      [result] = UpdateStats.stats_by_device(device)

      assert result.total_update_bytes == 4500
      assert result.total_saved_bytes == 450
      assert result.num_updates == 3
    end

    test "returns empty result for device with no stats", %{device: device} do
      result = UpdateStats.stats_by_device(device)
      assert result == []
    end

    test "handles device with only one stat record", %{
      device: device,
      deployment_group: deployment_group
    } do
      UpdateStats.log_stat(device, deployment_group, :fwup_full, 1024, 256)

      [result] = UpdateStats.stats_by_device(device)

      assert result.total_update_bytes == 1024
      assert result.total_saved_bytes == 256
      assert result.num_updates == 1
    end
  end

  describe "stats_by_deployment/1" do
    test "returns stats grouped by source firmware uuid for deployment", %{
      device: device,
      device2: device2,
      deployment_group: deployment_group,
      firmware: firmware,
      firmware2: firmware2
    } do
      # Device with firmware metadata (source uuid = firmware.uuid)
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}
      UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_full, 1000, 100)
      UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_delta, 1500, 150)

      # Device with different firmware metadata (source uuid = firmware2.uuid)
      device_with_metadata2 = %{device2 | firmware_metadata: %{uuid: firmware2.uuid}}
      UpdateStats.log_stat(device_with_metadata2, deployment_group, :fwup_full, 2000, 200)

      results = UpdateStats.stats_by_deployment(deployment_group)
      assert length(results) == 2

      # Results should be grouped by source_firmware_uuid
      firmware_stats =
        Enum.find(results, fn stat ->
          # We need to match against the aggregated results
          # 1000 + 1500
          stat.total_update_bytes == 2500
        end)

      # 100 + 150
      assert firmware_stats.total_saved_bytes == 250
      assert firmware_stats.num_updates == 2

      firmware2_stats =
        Enum.find(results, fn stat ->
          stat.total_update_bytes == 2000
        end)

      assert firmware2_stats.total_saved_bytes == 200
      assert firmware2_stats.num_updates == 1
    end

    test "returns empty result for deployment with no stats", %{
      deployment_group: deployment_group
    } do
      result = UpdateStats.stats_by_deployment(deployment_group)
      assert result == []
    end

    test "filters by deployment_id and target_firmware_uuid", %{
      device: device,
      deployment_group: deployment_group,
      deployment_group2: deployment_group2,
      firmware: firmware
    } do
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}

      # Stats for deployment_group
      UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_full, 1000, 100)

      # Stats for deployment_group2 (should not be included)
      UpdateStats.log_stat(device_with_metadata, deployment_group2, :fwup_full, 2000, 200)

      results = UpdateStats.stats_by_deployment(deployment_group)
      assert length(results) == 1

      [result] = results
      assert result.total_update_bytes == 1000
      assert result.total_saved_bytes == 100
      assert result.num_updates == 1
    end
  end

  describe "total_stats_by_product/1" do
    test "returns aggregated stats for all devices in a product", %{
      device: device,
      device2: device2,
      device4: device4,
      product: product,
      product2: product2,
      deployment_group: deployment_group
    } do
      # Stats for devices in product
      UpdateStats.log_stat(device, deployment_group, :fwup_full, 1000, 100)
      UpdateStats.log_stat(device2, deployment_group, :fwup_delta, 2000, 200)

      # Stats for device in product2 (should not be included)
      UpdateStats.log_stat(device4, deployment_group, :fwup_full, 500, 50)

      [result] = UpdateStats.total_stats_by_product(product)

      assert result.total_update_bytes == 3000
      assert result.total_saved_bytes == 300
      assert result.num_updates == 2
    end

    test "returns empty result for product with no stats", %{product: product} do
      result = UpdateStats.total_stats_by_product(product)
      assert result == []
    end

    test "handles product with devices having negative saved bytes", %{
      device: device,
      product: product,
      deployment_group: deployment_group
    } do
      UpdateStats.log_stat(device, deployment_group, :fwup_full, 1000, 100)
      UpdateStats.log_stat(device, deployment_group, :fwup_delta, 2000, -50)

      [result] = UpdateStats.total_stats_by_product(product)

      assert result.total_update_bytes == 3000
      # 100 + (-50)
      assert result.total_saved_bytes == 50
      assert result.num_updates == 2
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
      firmware: firmware
    } do
      device_with_metadata = %{device | firmware_metadata: %{uuid: firmware.uuid}}
      device2_with_metadata = %{device2 | firmware_metadata: %{uuid: firmware.uuid}}

      # Multiple stats for different scenarios
      UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_full, 1000, 100)
      UpdateStats.log_stat(device_with_metadata, deployment_group, :fwup_delta, 1500, 150)
      UpdateStats.log_stat(device2_with_metadata, deployment_group, :fwup_full, 2000, 200)
      UpdateStats.log_stat(device3, deployment_group2, :fwup_full, 3000, 300)

      # Test stats_by_device
      [device_stats] = UpdateStats.stats_by_device(device)
      assert device_stats.total_update_bytes == 2500
      assert device_stats.total_saved_bytes == 250
      assert device_stats.num_updates == 2

      # Test stats_by_deployment
      deployment_stats = UpdateStats.stats_by_deployment(deployment_group)
      assert length(deployment_stats) == 1
      [deployment_result] = deployment_stats
      # 1000 + 1500 + 2000
      assert deployment_result.total_update_bytes == 4500
      # 100 + 150 + 200
      assert deployment_result.total_saved_bytes == 450
      assert deployment_result.num_updates == 3

      # Test total_stats_by_product
      [product_stats] = UpdateStats.total_stats_by_product(product)
      # All updates for this product
      assert product_stats.total_update_bytes == 7500
      # All savings for this product
      assert product_stats.total_saved_bytes == 750
      assert product_stats.num_updates == 4
    end
  end

  # Helper function for creating random update stats (similar to LogLinesTest)
  defp create_random_update_stat(device, deployment_group) do
    update_bytes = Enum.random(100..5000)
    saved_bytes = Enum.random(-100..1000)
    type = Enum.random([:fwup_full, :fwup_delta])

    UpdateStats.log_stat(device, deployment_group, type, update_bytes, saved_bytes)
  end

  test "performance with many stats", %{
    device: device,
    deployment_group: deployment_group
  } do
    # Create many stats to test performance
    for _ <- 1..50 do
      create_random_update_stat(device, deployment_group)
    end

    [result] = UpdateStats.stats_by_device(device)
    assert result.num_updates == 51
    assert is_integer(result.total_update_bytes)
    assert is_integer(result.total_saved_bytes)
  end
end
