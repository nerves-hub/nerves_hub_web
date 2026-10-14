defmodule NervesHubWeb.API.DeviceMetricControllerTest do
  # Not async: these tests read and write the AnalyticsRepo (ClickHouse), which
  # has no sandbox, and one of them toggles the global :analytics_enabled.
  use NervesHubWeb.APIConnCase, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.DeviceMetric
  alias NervesHub.Devices.Metrics

  setup %{org: org, product: product} do
    {:ok, device} =
      Devices.create_device(%{
        identifier: "device-1234",
        description: "test device",
        tags: ["test"],
        org_id: org.id,
        product_id: product.id
      })

    :ok = Buffer.flush(DeviceMetric)
    AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")

    on_exit(fn ->
      :ok = Buffer.flush(DeviceMetric)
      AnalyticsRepo.query!("TRUNCATE TABLE device_metrics")
    end)

    [device: device, now: DateTime.utc_now()]
  end

  defp path(conn, org, product, device, params \\ []) do
    Routes.api_device_metric_path(conn, :index, org.name, product.name, device.identifier, params)
  end

  defp report(device, metrics, timestamp, firmware_uuid \\ nil) do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id,
      firmware_metadata: firmware_uuid && %{uuid: firmware_uuid}
    }

    {:ok, _stored} = Metrics.record(device_info, metrics, timestamp)
    :ok = Buffer.flush(DeviceMetric)
  end

  defp timestamps(response) do
    Enum.map(response["data"], fn %{"timestamp" => timestamp} ->
      {:ok, at, _offset} = DateTime.from_iso8601(timestamp)
      at
    end)
  end

  describe "index" do
    test "is empty for a device that has reported nothing", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 200)["data"] == []
    end

    test "puts a report's readings back together", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      report(device, %{"tank_level_mm" => 1250, "flow_total_litres" => 904.5}, now, "a-firmware-uuid")

      conn = get(conn, path(conn, org, product, device))

      assert [report] = json_response(conn, 200)["data"]
      assert report["metrics"] == %{"tank_level_mm" => 1250.0, "flow_total_litres" => 904.5}
      assert report["firmware_uuid"] == "a-firmware-uuid"
      assert {:ok, timestamp, _offset} = DateTime.from_iso8601(report["timestamp"])
      assert DateTime.compare(timestamp, now) == :eq
    end

    test "says null for a report taken before the device reported its firmware", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      report(device, %{"cpu_temp" => 41.2}, now)

      conn = get(conn, path(conn, org, product, device))

      assert [%{"firmware_uuid" => nil}] = json_response(conn, 200)["data"]
    end

    test "returns reports newest first", %{conn: conn, org: org, product: product, device: device, now: now} do
      older = DateTime.add(now, -600)
      report(device, %{"cpu_temp" => 40.0}, older)
      report(device, %{"cpu_temp" => 41.0}, now)

      conn = get(conn, path(conn, org, product, device))

      assert timestamps(json_response(conn, 200)) == [now, older]
    end

    test "does not return another device's reports", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      {:ok, other} = Devices.create_device(%{identifier: "device-5678", org_id: org.id, product_id: product.id})

      report(other, %{"cpu_temp" => 99.0}, now)
      report(device, %{"cpu_temp" => 41.0}, now)

      conn = get(conn, path(conn, org, product, device))

      assert [%{"metrics" => %{"cpu_temp" => 41.0}}] = json_response(conn, 200)["data"]
    end

    test "is reachable on the short device URL", %{conn: conn, device: device, now: now} do
      report(device, %{"cpu_temp" => 41.0}, now)

      conn = get(conn, Routes.api_device_metric_path(conn, :index, device.identifier))

      assert [_report] = json_response(conn, 200)["data"]
    end

    test "is refused for a user outside the organization", %{conn2: conn2, org: org, product: product, device: device} do
      assert_error_sent(404, fn -> get(conn2, path(conn2, org, product, device)) end)
      |> assert_authorization_error(404)
    end
  end

  describe "index, narrowed to some metrics" do
    setup %{device: device, now: now} do
      report(device, %{"tank_level_mm" => 1200, "cpu_temp" => 40.0}, DateTime.add(now, -600))
      report(device, %{"cpu_temp" => 41.0}, now)
      :ok
    end

    test "keeps only those readings, and only reports that carried one", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device, key: "tank_level_mm"))

      assert [%{"metrics" => metrics}] = json_response(conn, 200)["data"]
      assert metrics == %{"tank_level_mm" => 1200.0}
    end

    test "several metrics, comma separated", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, key: "tank_level_mm, cpu_temp"))

      assert [%{"metrics" => newest}, %{"metrics" => oldest}] = json_response(conn, 200)["data"]
      assert newest == %{"cpu_temp" => 41.0}
      assert oldest == %{"tank_level_mm" => 1200.0, "cpu_temp" => 40.0}
    end

    test "a name never reported matches nothing", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, key: "valve_open"))

      assert json_response(conn, 200)["data"] == []
    end

    test "an empty key is no filter at all", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, key: " "))

      assert length(json_response(conn, 200)["data"]) == 2
    end
  end

  describe "index, by time" do
    setup %{device: device, now: now} do
      for minutes <- [30, 20, 10, 0] do
        report(
          device,
          %{"cpu_temp" => 40.0 + minutes, "mem_used_percent" => 30.0},
          DateTime.add(now, -minutes, :minute)
        )
      end

      :ok
    end

    test "since is inclusive", %{conn: conn, org: org, product: product, device: device, now: now} do
      since = DateTime.add(now, -10, :minute)

      conn = get(conn, path(conn, org, product, device, since: DateTime.to_iso8601(since)))

      assert timestamps(json_response(conn, 200)) == [now, since]
    end

    test "before excludes the report it names, so it can page", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      now: now
    } do
      first_page = conn |> get(path(conn, org, product, device, limit: 2)) |> json_response(200)
      assert timestamps(first_page) == [now, DateTime.add(now, -10, :minute)]

      oldest = first_page["data"] |> List.last() |> Map.fetch!("timestamp")
      second_page = conn |> get(path(conn, org, product, device, limit: 2, before: oldest)) |> json_response(200)

      assert timestamps(second_page) == [DateTime.add(now, -20, :minute), DateTime.add(now, -30, :minute)]
    end

    test "limit counts reports, not readings", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, limit: 1))

      assert [%{"metrics" => metrics}] = json_response(conn, 200)["data"]
      assert map_size(metrics) == 2
    end

    test "oldest first with order=asc", %{conn: conn, org: org, product: product, device: device, now: now} do
      conn = get(conn, path(conn, org, product, device, order: "asc", limit: 2))

      assert timestamps(json_response(conn, 200)) == [DateTime.add(now, -30, :minute), DateTime.add(now, -20, :minute)]
    end
  end

  describe "index, refusing what it cannot use" do
    test "a timestamp it cannot read", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, since: "yesterday"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "since must be an ISO 8601 timestamp"
    end

    test "a limit outside 1 to 1000", %{conn: conn, org: org, product: product, device: device} do
      for limit <- ["0", "1001", "lots"] do
        conn = get(conn, path(conn, org, product, device, limit: limit))

        assert json_response(conn, 422)["errors"]["detail"] =~ "limit must be a whole number between 1 and 1000"
      end
    end

    test "an order it does not know", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, path(conn, org, product, device, order: "sideways"))

      assert json_response(conn, 422)["errors"]["detail"] =~ "order must be asc or desc"
    end
  end

  describe "index, without an analytics database" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
    end

    test "says so instead of answering with an empty list", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn = get(conn, path(conn, org, product, device))

      assert json_response(conn, 501)["errors"]["detail"] =~ "device metric history is not stored"
    end
  end
end
