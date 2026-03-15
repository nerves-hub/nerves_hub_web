defmodule NervesHubWeb.API.V2.DeviceConnectionTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures
  alias NervesHub.Devices.Connections

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    {:ok, connection} = Connections.device_connecting(device, product.id)
    :ok = Connections.device_connected(device, connection.id)

    [device: device, firmware: firmware, connection_id: connection.id]
  end

  describe "index" do
    test "lists device connections", %{conn: conn} do
      conn = get(conn, "/api/v2/device-connections")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a device connection by id", %{conn: conn, connection_id: id} do
      conn = get(conn, "/api/v2/device-connections/#{id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["status"] == "connected"
    end
  end

  describe "list_by_device" do
    test "lists connections by device", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/device-connections/by-device/#{device.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end
end
