defmodule NervesHub.DeviceMetricsTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    product2 = Fixtures.product_fixture(user, org, %{name: "Second product"})
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
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

      assert {:ok, 7} = Metrics.save_metrics(device.id, metrics)
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

  describe "get_latest_metric/1" do
    test "returns nil when no metrics exist", %{device: device} do
      assert Metrics.get_latest_metric(device.id) == nil
    end

    test "returns the latest metric when multiple exist", %{device: device} do
      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 10})
      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 99})

      result = Metrics.get_latest_metric(device.id)

      assert result.value == 99.0
    end
  end

  describe "get_latest_metric/2" do
    test "returns nil when no metrics for that key", %{device: device} do
      assert Metrics.get_latest_metric(device.id, "cpu_temp") == nil
    end
  end

  describe "get_latest_timestamp_for_device/1" do
    test "returns nil when no metrics exist", %{device: device} do
      assert Metrics.get_latest_timestamp_for_device(device.id) == nil
    end

    test "returns the timestamp when metrics exist", %{device: device} do
      {:ok, saved} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 42})

      assert Metrics.get_latest_timestamp_for_device(device.id) == saved.inserted_at
    end
  end

  describe "get_latest_metric_set/1" do
    test "returns empty map when no metrics exist", %{device: device} do
      assert Metrics.get_latest_metric_set(device.id) == %{}
    end

    test "returns a map of key→value with a timestamp key when metrics exist", %{device: device} do
      {:ok, _} =
        Metrics.save_metrics(device.id, %{"cpu_temp" => 55.0, "mem_used_percent" => 30.0})

      result = Metrics.get_latest_metric_set(device.id)

      assert result["cpu_temp"] == 55.0
      assert result["mem_used_percent"] == 30.0
      assert Map.has_key?(result, "timestamp")
    end
  end

  describe "save_metrics/2" do
    test "with empty map returns {:ok, 0}", %{device: device} do
      assert Metrics.save_metrics(device.id, %{}) == {:ok, 0}
    end
  end

  describe "truncate_device_metrics/0" do
    test "deletes old metrics and returns {:ok, count}", %{device: device} do
      days_to_retain = Application.get_env(:nerves_hub, :device_health_days_to_retain)

      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 42})

      old_time = DateTime.shift(DateTime.utc_now(), day: -(days_to_retain + 1))

      NervesHub.Repo.update_all(
        DeviceMetric,
        set: [inserted_at: old_time]
      )

      assert {:ok, count} = Metrics.truncate_device_metrics()
      assert count >= 1
    end
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

  describe "distinct_keys/1" do
    test "returns sorted distinct keys for devices in the product", %{
      device: device,
      product: product
    } do
      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 42})
      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 43})
      {:ok, _} = Metrics.save_metric(%{device_id: device.id, key: "mem_used_percent", value: 30})

      keys = Metrics.distinct_keys(product.id)

      assert keys == ["cpu_temp", "mem_used_percent"]
    end

    test "excludes keys from devices in other products", %{
      device2: device2,
      product: product
    } do
      {:ok, _} = Metrics.save_metric(%{device_id: device2.id, key: "cpu_temp", value: 42})

      assert Metrics.distinct_keys(product.id) == []
    end
  end
end
