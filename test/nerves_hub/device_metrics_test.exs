defmodule NervesHub.DeviceMetricsTest do
  use NervesHub.DataCase, async: false

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    product2 = Fixtures.product_fixture(user, org, %{name: "Second product"})
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    device = Fixtures.device_fixture(org, product, firmware)
    device2 = Fixtures.device_fixture(org, product2, firmware)

    {:ok, %{device: device, device2: device2, product: product, product2: product2}}
  end

  describe "saving metrics" do
    test "save single metric", %{device: device} do
      device_id = device.id
      params = %{device_id: device_id, key: "cpu_temp", value: 42}

      assert {:ok, %DeviceMetric{device_id: ^device_id, key: "cpu_temp", value: 42.0}} =
               Metrics.save_metric(params)
    end

    test "save single metric, ensure formatting of key", %{device: device} do
      device_id = device.id
      params = %{device_id: device_id, key: "cpu_ temp", value: 42}

      assert {:ok, %DeviceMetric{device_id: ^device_id, key: "cpu_temp", value: 42.0}} =
               Metrics.save_metric(params)
    end

    test "save map of metrics", %{device: device} do
      metrics = %{
        "cpu_temp" => 41.381,
        "load_15min" => 0.06,
        "load_1min" => 0.55,
        "load_5min" => 0.15,
        "size_mb" => 7892,
        "used_mb" => 172,
        "used_percent" => 2
      }

      assert {:ok, result} = Metrics.save_metrics(device.id, metrics)
      assert length(result) == map_size(metrics)
    end
  end

  describe "get metrics for device" do
    test "get device metrics for key", %{device: device, device2: device2} do
      assert {:ok, %DeviceMetric{}} =
               Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 42})

      assert {:ok, %DeviceMetric{}} =
               Metrics.save_metric(%{device_id: device2.id, key: "cpu_temp", value: 43})

      res = Metrics.get_device_metrics_by_key(device.id, "cpu_temp")

      # Assert result only include device metrics
      assert length(res) == 1
    end

    test "assert no metrics gives empty list", %{device: device} do
      assert [] = Metrics.get_device_metrics_by_key(device.id, "cpu_temp")
    end

    # test "get device metrics within time frame"
  end

  describe "get metrics for product" do
    test "get product metrics by key", %{
      device: device,
      device2: device2,
      product: product
    } do
      assert {:ok, %DeviceMetric{}} =
               Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 42})

      assert {:ok, %DeviceMetric{}} =
               Metrics.save_metric(%{device_id: device.id, key: "load_1min", value: 1.2})

      assert {:ok, %DeviceMetric{}} =
               Metrics.save_metric(%{device_id: device2.id, key: "cpu_temp", value: 43})

      res = Metrics.get_product_metrics_by_key(product.id, "cpu_temp")

      # Assert metrics from devices belonging to other products are excluded,
      # and that other metric keys are excluded
      assert length(res) == 1
    end
  end
end
