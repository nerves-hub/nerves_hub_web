defmodule NervesHub.Devices.HealthStatusTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.HealthStatus
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, %{device: device, thresholds: HealthStatus.default_thresholds()}}
  end

  describe "status based on latest metrics" do
    test "device status is unknown - no metrics", %{device: device} do
      assert :unknown = HealthStatus.latest_metrics_status(device)
    end

    test "device status is unknown - metrics without thresholds", %{device: device} do
      metrics = %{
        "other_metric" => 45
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)
      assert :unknown = HealthStatus.latest_metrics_status(device)
    end

    test "device status is healthy", %{device: device, thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 3
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)
      assert :healthy = HealthStatus.latest_metrics_status(device)
    end

    test "device status is warning", %{device: device, thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)
      assert :warning = HealthStatus.latest_metrics_status(device)
    end

    test "device status is unhealthy", %{device: device, thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)
      assert :unhealthy = HealthStatus.latest_metrics_status(device)
    end
  end
end
