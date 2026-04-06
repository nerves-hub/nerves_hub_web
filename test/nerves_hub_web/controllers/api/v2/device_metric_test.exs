defmodule NervesHubWeb.API.V2.DeviceMetricTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Devices.Metrics

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, metric} = Metrics.save_metric(%{device_id: device.id, key: "cpu_temp", value: 45.5})

    [device: device, metric: metric]
  end

  describe "index" do
    test "lists device metrics", %{conn: conn} do
      conn = get(conn, "/api/v2/device-metrics")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a device metric by id", %{conn: conn, metric: metric} do
      conn = get(conn, "/api/v2/device-metrics/#{metric.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["key"] == "cpu_temp"
      assert resp["data"]["attributes"]["value"] == 45.5
    end
  end

  describe "list_by_device" do
    test "lists metrics by device", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/device-metrics/by-device/#{device.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end
end
