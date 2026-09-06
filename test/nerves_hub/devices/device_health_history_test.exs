defmodule NervesHub.Devices.DeviceHealthHistoryTest do
  # Not async: reads and writes the AnalyticsRepo (ClickHouse), which no
  # sandbox rolls back.
  use NervesHub.DataCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.DeviceHealth
  alias NervesHub.Devices.DeviceHealthHistory
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Devices.Metrics
  alias NervesHub.Fixtures
  alias NervesHub.Products.HealthProfiles

  setup %{tmp_dir: tmp_dir} do
    for table <- ["device_metrics", "device_health_history"] do
      AnalyticsRepo.query!("TRUNCATE TABLE #{table}")
    end

    on_exit(fn ->
      for table <- ["device_metrics", "device_health_history"] do
        AnalyticsRepo.query!("TRUNCATE TABLE #{table}")
      end
    end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    device_info = %{
      device_id: device.id,
      product_id: device.product_id,
      org_id: device.org_id,
      firmware_metadata: device.firmware_metadata
    }

    {:ok, %{org: org, product: product, device: device, device_info: device_info}}
  end

  # Readings land the way production writes them, flushed so the judgement
  # reads them back rather than only counting them in hand.
  defp store_reading(device, key, value) do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    {:ok, 1} = Metrics.record(device_info, %{key => value})
    :ok = Buffer.flush(DeviceMetric)
  end

  defp history(device) do
    :ok = Buffer.flush(DeviceHealthHistory)

    DeviceHealthHistory
    |> where(device_id: ^device.id)
    |> order_by([h], asc: h.timestamp)
    |> AnalyticsRepo.all()
  end

  defp reading(key, value), do: [{key, DateTime.utc_now(), value}]

  describe "recording transitions" do
    test "a device's first verdict is recorded", %{org: org, product: product, device: device, device_info: info} do
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 20.0))

      assert [row] = history(device)
      assert row.status == "healthy"
      assert row.status_reasons == ""
      assert row.device_id == device.id
      assert row.product_id == product.id
      assert row.org_id == org.id
    end

    test "the row carries the moment the verdict was stored", %{device: device, device_info: info} do
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 20.0))

      assert [row] = history(device)
      stored = Repo.get_by(DeviceHealth, device_id: device.id)

      assert DateTime.diff(row.timestamp, stored.updated_at, :millisecond) == 0
    end

    test "a verdict that has not moved records nothing further", %{device: device, device_info: info} do
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 20.0))
      store_reading(device, "cpu_usage_percent", 20.0)
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 21.0))
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 22.0))

      assert [%{status: "healthy"}] = history(device)
    end

    test "a move to unhealthy records the reasons that engaged it", %{device: device, device_info: info} do
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 20.0))

      # Enough breaching readings in the window to carry the majority.
      for _ <- 1..3, do: store_reading(device, "cpu_usage_percent", 95.0)
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 95.0))

      assert [%{status: "healthy"}, %{status: "unhealthy", status_reasons: reasons}] = history(device)

      # Stored as JSON, naming the threshold and period in force at the time —
      # which is what keeps the row true after somebody edits the profile.
      assert %{"unhealthy" => %{"cpu_usage_percent" => reason}} = Jason.decode!(reasons)
      assert reason["threshold"] == 90.0
      assert reason["period_seconds"] == 3600
    end

    test "each further move is its own row", %{product: product, device: device, device_info: info} do
      profile = HealthProfiles.resolve(product.id, nil)
      cpu = Enum.find(profile.metrics, &(&1.key == "cpu_usage_percent"))

      # A one-minute window, so a step's own readings are the whole window
      # once the previous step's have been cleared out of it. Three of them
      # each time, so the majority is carried rather than decided by a single
      # reading.
      {:ok, _} =
        HealthProfiles.update_metric(cpu, %{
          "warning_period_seconds" => "60",
          "alert_period_seconds" => "60"
        })

      for value <- [20.0, 85.0, 95.0, 20.0] do
        # The window has moved on: what came before is no longer in it.
        AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")
        for _ <- 1..3, do: store_reading(device, "cpu_usage_percent", value)

        :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", value))
      end

      assert ["healthy", "warning", "unhealthy", "healthy"] = Enum.map(history(device), & &1.status)
    end
  end

  describe "without analytics" do
    setup do
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, true) end)
    end

    test "nothing is recorded, and the verdict still saves", %{device: device, device_info: info} do
      :ok = HealthEvaluation.evaluate_and_save(info, reading("cpu_usage_percent", 95.0))

      # The legacy instantaneous check still ran and stored its verdict.
      assert Repo.get_by(DeviceHealth, device_id: device.id).status == :unhealthy

      assert history(device) == []
    end
  end
end
