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

  describe "get device status from metrics map" do
    test "status is unknown - no metrics" do
      assert :unknown = HealthStatus.calculate_metrics_status(%{})
    end

    test "status is unknown - metrics without thresholds" do
      metrics = %{
        "other_metric" => 45
      }

      assert :unknown = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is healthy", %{thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 3
      }

      assert :healthy = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is healthy - with unknown metrics", %{
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 3,
        "unknown" => 12
      }

      assert :healthy = HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is warning", %{thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      assert {:warning, %{warning: ["cpu_usage_percent"], unhealthy: []}} =
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is warning - reports multiple warnings", %{
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning,
        "mem_used_percent" => thresholds["mem_used_percent"].warning,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      assert {:warning, %{warning: ["mem_used_percent", "cpu_usage_percent"], unhealthy: []}} =
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy", %{thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      assert {:unhealthy, %{warning: [], unhealthy: ["mem_used_percent"]}} =
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy - also reports warnings", %{
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning
      }

      assert {:unhealthy, %{warning: ["disk_used_percentage"], unhealthy: ["mem_used_percent"]}} =
               HealthStatus.calculate_metrics_status(metrics)
    end

    test "status is unhealthy - reports multiple unhealthy metrics", %{
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].unhealthy,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning
      }

      assert {:unhealthy,
              %{
                warning: ["disk_used_percentage"],
                unhealthy: ["mem_used_percent", "cpu_usage_percent"]
              }} =
               HealthStatus.calculate_metrics_status(metrics)
    end
  end

  describe "status with report, based on latest metrics" do
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

    test "device status is healthy - with unknown metrics", %{
      device: device,
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].warning - 2,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 3,
        "unknown" => 12
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

      assert {:warning, %{warning: ["cpu_usage_percent"], unhealthy: []}} =
               HealthStatus.latest_metrics_status(device)
    end

    test "device status is warning - reports multiple warnings", %{
      device: device,
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning,
        "mem_used_percent" => thresholds["mem_used_percent"].warning,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)

      assert {:warning, %{warning: ["mem_used_percent", "cpu_usage_percent"], unhealthy: []}} =
               HealthStatus.latest_metrics_status(device)
    end

    test "device status is unhealthy", %{device: device, thresholds: thresholds} do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning - 1
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)

      assert {:unhealthy, %{warning: [], unhealthy: ["mem_used_percent"]}} =
               HealthStatus.latest_metrics_status(device)
    end

    test "device status is unhealthy - also reports warnings", %{
      device: device,
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].warning - 1,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)

      assert {:unhealthy, %{warning: ["disk_used_percentage"], unhealthy: ["mem_used_percent"]}} =
               HealthStatus.latest_metrics_status(device)
    end

    test "status is unhealthy - reports multiple unhealthy metrics", %{
      device: device,
      thresholds: thresholds
    } do
      metrics = %{
        "cpu_usage_percent" => thresholds["cpu_usage_percent"].unhealthy,
        "mem_used_percent" => thresholds["mem_used_percent"].unhealthy,
        "disk_used_percentage" => thresholds["disk_used_percentage"].warning
      }

      {:ok, _} = Metrics.save_metrics(device.id, metrics)

      assert {:unhealthy,
              %{
                warning: ["disk_used_percentage"],
                unhealthy: ["mem_used_percent", "cpu_usage_percent"]
              }} =
               HealthStatus.latest_metrics_status(device)
    end
  end
end
