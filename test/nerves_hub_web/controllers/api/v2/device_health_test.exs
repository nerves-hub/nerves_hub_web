defmodule NervesHubWeb.API.V2.DeviceHealthTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Devices

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, health} =
      Devices.save_device_health(%{
        "device_id" => device.id,
        "data" => %{"cpu" => 50},
        "status" => "healthy"
      })

    [device: device, health: health]
  end

  describe "index" do
    test "lists device health records", %{conn: conn} do
      conn = get(conn, "/api/v2/device-health")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a device health by id", %{conn: conn, health: health} do
      conn = get(conn, "/api/v2/device-health/#{health.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["status"] == "healthy"
    end
  end

  describe "list_by_device" do
    test "lists health records by device", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/device-health/by-device/#{device.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end
end
