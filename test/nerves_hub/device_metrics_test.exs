defmodule NervesHub.DeviceMetricsTest do
  # Not async: `record/3` writes ClickHouse through the shared
  # `NervesHub.Analytics.Buffer`, and these tests truncate the table and flush
  # the buffer to read back what they just wrote.
  use NervesHub.DataCase, async: false

  import Ecto.Query

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Products.Notification

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    product2 = Fixtures.product_fixture(user, org, %{name: "Second product"})
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    device2 = Fixtures.device_fixture(org, product2, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")
    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_metrics") end)

    {:ok,
     %{
       device: device,
       device2: device2,
       device_info: device_info(device),
       device_info2: device_info(device2),
       product: product,
       product2: product2
     }}
  end

  describe "record/3" do
    test "stores one ClickHouse row per reading, scoped to the org and product", %{
      device: device,
      device_info: device_info
    } do
      assert {:ok, 2} = Metrics.record(device_info, %{"cpu_temp" => 41.5, "mem_used_percent" => 30})

      assert [cpu, mem] = analytics_rows(device)

      assert cpu.key == "cpu_temp"
      assert cpu.value == 41.5
      assert cpu.org_id == device.org_id
      assert cpu.product_id == device.product_id
      assert cpu.device_id == device.id

      assert mem.key == "mem_used_percent"
      # Integers arrive as integers from a device and are stored as floats.
      assert mem.value == 30.0
    end

    test "shares one timestamp across the readings in a report", %{device: device, device_info: device_info} do
      timestamp = DateTime.truncate(DateTime.utc_now(), :microsecond)

      assert {:ok, 2} = Metrics.record(device_info, %{"cpu_temp" => 1.0, "load_1min" => 2.0}, timestamp)

      assert [%{timestamp: ^timestamp}, %{timestamp: ^timestamp}] = analytics_rows(device)
    end

    test "an empty report stores nothing", %{device: device, device_info: device_info} do
      assert {:ok, 0} = Metrics.record(device_info, %{})

      assert analytics_rows(device) == []
      assert Metrics.get_latest_metric_set(device.id) == %{}
    end

    test "records the firmware the device was running", %{device: device, device_info: device_info} do
      device_info = %{device_info | firmware_metadata: %{uuid: "abc-123"}}

      assert {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 41.5})

      assert [%{firmware_uuid: "abc-123"}] = analytics_rows(device)
    end

    test "a device that has reported no firmware metadata gets an empty string", %{
      device: device,
      device_info: device_info
    } do
      assert {:ok, 1} = Metrics.record(%{device_info | firmware_metadata: nil}, %{"cpu_temp" => 41.5})

      assert [%{firmware_uuid: ""}] = analytics_rows(device)
    end

    test "readings keep the firmware they were taken under, not the newest one", %{
      device: device,
      device_info: device_info
    } do
      before_update = %{device_info | firmware_metadata: %{uuid: "1.3.0-uuid"}}
      after_update = %{device_info | firmware_metadata: %{uuid: "1.4.0-uuid"}}

      {:ok, 1} = Metrics.record(before_update, %{"mem_used_percent" => 30}, at(-120))
      {:ok, 1} = Metrics.record(after_update, %{"mem_used_percent" => 55}, at(-60))

      # What the whole column is for: the same metric, split by release.
      assert [%{value: 30.0, firmware_uuid: "1.3.0-uuid"}, %{value: 55.0, firmware_uuid: "1.4.0-uuid"}] =
               analytics_rows(device)
    end

    test "an older report does not move the latest set backwards", %{device: device, device_info: device_info} do
      now = DateTime.utc_now()

      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42}, now)
      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 1}, DateTime.add(now, -60, :second))

      # A batch can carry readings older than ones already stored -- a device
      # that buffered across a disconnect sends them on reconnect -- and the
      # last message to arrive is not necessarily the latest reading.
      assert Metrics.get_latest_metric_set(device.id)["cpu_temp"] == 42.0

      # Both are still in the history; only the latest set is guarded.
      assert [%{value: 1.0}, %{value: 42.0}] = analytics_rows(device)
    end

    test "a newer report does move it", %{device: device, device_info: device_info} do
      now = DateTime.utc_now()

      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42}, DateTime.add(now, -60, :second))
      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 43}, now)

      assert Metrics.get_latest_metric_set(device.id)["cpu_temp"] == 43.0
    end

    test "strips spaces from metric names", %{device: device, device_info: device_info} do
      assert {:ok, 1} = Metrics.record(device_info, %{"cpu_ temp" => 42})

      assert [%{key: "cpu_temp"}] = analytics_rows(device)
    end

    test "drops readings that are not numbers, and keeps the rest", %{device: device, device_info: device_info} do
      assert {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42, "uptime" => "a while"})

      assert [%{key: "cpu_temp"}] = analytics_rows(device)
    end
  end

  describe "record/3 with metric names that are too long" do
    setup do
      %{long_key: String.duplicate("x", Metrics.max_key_bytes() + 1)}
    end

    test "drops the reading and keeps its neighbours", %{
      device: device,
      device_info: device_info,
      long_key: long_key
    } do
      assert {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42, long_key => 1})

      assert [%{key: "cpu_temp"}] = analytics_rows(device)
    end

    test "keeps a name of exactly the maximum length", %{device: device, device_info: device_info} do
      key = String.duplicate("x", Metrics.max_key_bytes())

      assert {:ok, 1} = Metrics.record(device_info, %{key => 1})

      assert [%{key: ^key}] = analytics_rows(device)
    end

    test "raises a notification naming the device and the offending metric", %{
      device: device,
      device_info: device_info,
      product: product,
      long_key: long_key
    } do
      assert {:ok, 0} = Metrics.record(device_info, %{long_key => 1})

      assert [notification] = notifications(product)
      assert notification.level == :warning
      assert notification.title =~ "metric names that were too long"
      assert notification.message =~ device.identifier
      assert notification.metadata["example_key"] == long_key
      assert notification.metadata["count"] == 1
    end

    test "a device repeating itself does not repeat the notification", %{
      device_info: device_info,
      product: product,
      long_key: long_key
    } do
      assert {:ok, 0} = Metrics.record(device_info, %{long_key => 1})
      assert {:ok, 0} = Metrics.record(device_info, %{long_key => 1})

      # Throttled per device, so the second report does not even reach the
      # upsert that would bump the count.
      assert [%{occurrence_count: 1}] = notifications(product)
    end

    test "one noisy device does not silence another", %{
      device_info: device_info,
      device_info2: device_info2,
      product: product,
      product2: product2,
      long_key: long_key
    } do
      assert {:ok, 0} = Metrics.record(device_info, %{long_key => 1})
      assert {:ok, 0} = Metrics.record(device_info2, %{long_key => 1})

      assert [_] = notifications(product)
      assert [_] = notifications(product2)
    end
  end

  describe "record/3 with too many metrics" do
    setup do
      max_keys = Metrics.max_keys_per_report()

      # Names that sort in the order they are numbered, so the test can say
      # which readings survive.
      metrics = Map.new(1..(max_keys + 3), &{"metric_#{String.pad_leading(to_string(&1), 3, "0")}", &1 * 1.0})

      %{max_keys: max_keys, metrics: metrics}
    end

    test "keeps the maximum, in sorted order", %{
      device: device,
      device_info: device_info,
      max_keys: max_keys,
      metrics: metrics
    } do
      assert {:ok, ^max_keys} = Metrics.record(device_info, metrics)

      stored = device |> analytics_rows() |> Enum.map(& &1.key)

      assert stored == metrics |> Map.keys() |> Enum.sort() |> Enum.take(max_keys)
    end

    test "raises a notification saying how many were sent", %{
      device: device,
      device_info: device_info,
      product: product,
      max_keys: max_keys,
      metrics: metrics
    } do
      assert {:ok, ^max_keys} = Metrics.record(device_info, metrics)

      assert [notification] = notifications(product)
      assert notification.level == :warning
      assert notification.title =~ "more metrics than NervesHub will store"
      assert notification.message =~ device.identifier
      assert notification.metadata["reported"] == max_keys + 3
      assert notification.metadata["max_keys"] == max_keys
    end

    test "the cap is configurable", %{device: device, device_info: device_info, metrics: metrics} do
      previous = Application.get_env(:nerves_hub, :device_metrics)
      Application.put_env(:nerves_hub, :device_metrics, max_keys_per_report: 2)
      on_exit(fn -> Application.put_env(:nerves_hub, :device_metrics, previous) end)

      assert Metrics.max_keys_per_report() == 2
      assert {:ok, 2} = Metrics.record(device_info, metrics)
      assert length(analytics_rows(device)) == 2
    end
  end

  describe "get_device_metrics_by_key/3" do
    test "returns only the given device's readings of that key", %{
      device: device,
      device_info: device_info,
      device_info2: device_info2
    } do
      {:ok, 2} = Metrics.record(device_info, %{"cpu_temp" => 42, "load_1min" => 1.0})
      {:ok, 1} = Metrics.record(device_info2, %{"cpu_temp" => 43})

      :ok = Buffer.flush(DeviceMetric)

      assert [%{value: 42.0}] = Metrics.get_device_metrics_by_key(device, "cpu_temp", {"hour", 1})
    end

    test "excludes readings older than the time frame", %{device: device, device_info: device_info} do
      long_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42}, long_ago)
      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 43})

      :ok = Buffer.flush(DeviceMetric)

      assert [%{value: 43.0}] = Metrics.get_device_metrics_by_key(device, "cpu_temp", {"hour", 1})
      assert [%{value: 42.0}, %{value: 43.0}] = Metrics.get_device_metrics_by_key(device, "cpu_temp", {"day", 1})
    end

    test "returns an empty list when nothing has been reported", %{device: device} do
      assert [] = Metrics.get_device_metrics_by_key(device, "cpu_temp", {"hour", 1})
    end

    test "returns an empty list where the deployment has no ClickHouse", %{
      device: device,
      device_info: device_info
    } do
      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42})
      :ok = Buffer.flush(DeviceMetric)

      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, true) end)

      assert [] = Metrics.get_device_metrics_by_key(device, "cpu_temp", {"hour", 1})

      # The latest set is PostgreSQL, so the device page still has numbers.
      assert Metrics.get_latest_metric_set(device.id)["cpu_temp"] == 42.0
    end
  end

  describe "get_latest_metric_set/1" do
    test "returns an empty map when nothing has been reported", %{device: device} do
      assert Metrics.get_latest_metric_set(device.id) == %{}
    end

    test "returns the most recent reading of every key, with its timestamp", %{
      device: device,
      device_info: device_info
    } do
      {:ok, 2} = Metrics.record(device_info, %{"cpu_temp" => 55.0, "mem_used_percent" => 30.0})

      result = Metrics.get_latest_metric_set(device.id)

      assert result["cpu_temp"] == 55.0
      assert result["mem_used_percent"] == 30.0
      assert Map.has_key?(result, "timestamp")
    end
  end

  describe "distinct_keys/1" do
    test "returns sorted distinct keys for devices in the product", %{
      device_info: device_info,
      product: product
    } do
      {:ok, 2} = Metrics.record(device_info, %{"mem_used_percent" => 30, "cpu_temp" => 42})

      assert Metrics.distinct_keys(product.id) == ["cpu_temp", "mem_used_percent"]
    end

    test "reflects what devices report now, not everything they ever reported", %{
      device_info: device_info,
      product: product
    } do
      {:ok, 1} = Metrics.record(device_info, %{"cpu_temp" => 42})
      {:ok, 1} = Metrics.record(device_info, %{"mem_used_percent" => 30})

      # A report replaces the device's latest set, so a metric the firmware has
      # stopped collecting stops being offered in the autosuggest list.
      assert Metrics.distinct_keys(product.id) == ["mem_used_percent"]
    end

    test "excludes keys from devices in other products", %{device_info2: device_info2, product: product} do
      {:ok, 1} = Metrics.record(device_info2, %{"cpu_temp" => 42})

      assert Metrics.distinct_keys(product.id) == []
    end
  end

  defp device_info(device) do
    %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }
  end

  defp at(seconds_ago), do: DateTime.add(DateTime.utc_now(), seconds_ago, :second)

  # Everything buffered before this call is readable when it returns.
  defp analytics_rows(device) do
    :ok = Buffer.flush(DeviceMetric)

    DeviceMetric
    |> where(device_id: ^device.id)
    |> order_by(asc: :key, asc: :timestamp)
    |> AnalyticsRepo.all()
  end

  defp notifications(product) do
    Notification
    |> where(product_id: ^product.id)
    |> order_by(asc: :event_key)
    |> Repo.all()
  end
end
