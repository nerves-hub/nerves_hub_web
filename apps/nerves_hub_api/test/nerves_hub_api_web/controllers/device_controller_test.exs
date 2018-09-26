defmodule NervesHubAPIWeb.DeviceControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true
  alias NervesHubCore.{Devices, Fixtures}

  describe "create devices" do
    test "renders device when data is valid", %{conn: conn, org: org} do
      identifier = "api-device-1234"
      device = %{identifier: identifier, description: "test device", tags: ["test"]}

      conn = post(conn, device_path(conn, :create, org.name), device)
      assert json_response(conn, 201)["data"]

      conn = get(conn, device_path(conn, :show, org.name, device.identifier))
      assert json_response(conn, 200)["data"]["identifier"] == identifier
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete devices" do
    test "deletes chosen device", %{conn: conn, org: org} do
      product = Fixtures.product_fixture(org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, firmware)

      [to_delete | _] = Devices.get_devices(org)
      conn = delete(conn, device_path(conn, :delete, org.name, to_delete.identifier))
      assert json_response(conn, 204)["data"]

      conn = get(conn, device_path(conn, :show, org.name, to_delete.identifier))
      assert json_response(conn, 404)
    end
  end

  describe "update devices" do
    test "updates chosen device", %{conn: conn, org: org} do
      product = Fixtures.product_fixture(org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, firmware)

      [to_update | _] = Devices.get_devices(org)

      conn =
        put(conn, device_path(conn, :update, org.name, to_update.identifier), %{
          tags: ["a", "b", "c", "d"]
        })

      assert json_response(conn, 204)["data"]

      conn = get(conn, device_path(conn, :show, org.name, to_update.identifier))
      assert json_response(conn, 200)
      assert conn.assigns.device.tags == ["a", "b", "c", "d"]
    end
  end
end
