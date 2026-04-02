defmodule NervesHubWeb.API.V2.DeviceCertificateTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)
    %{db_cert: device_cert} = Fixtures.device_certificate_fixture(device)

    [device: device, device_cert: device_cert]
  end

  describe "index" do
    test "lists device certificates", %{conn: conn} do
      conn = get(conn, "/api/v2/device-certificates")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      assert length(resp["data"]) >= 1
    end
  end

  describe "show" do
    test "returns a device certificate", %{conn: conn, device_cert: device_cert} do
      conn = get(conn, "/api/v2/device-certificates/#{device_cert.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["serial"] == device_cert.serial
    end
  end

  describe "list_by_device" do
    test "lists device certificates by device", %{conn: conn, device: device, device_cert: device_cert} do
      conn = get(conn, "/api/v2/device-certificates/by-device/#{device.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      serials = Enum.map(resp["data"], & &1["attributes"]["serial"])
      assert device_cert.serial in serials
    end
  end

  describe "get_by_device_and_serial" do
    test "returns a cert by device and serial", %{conn: conn, device: device, device_cert: device_cert} do
      conn = get(conn, "/api/v2/device-certificates/by-device/#{device.id}/serial/#{device_cert.serial}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["serial"] == device_cert.serial
    end
  end

  describe "delete" do
    test "deletes a device certificate", %{conn: conn, device_cert: device_cert} do
      conn = delete(conn, "/api/v2/device-certificates/#{device_cert.id}")
      assert response(conn, 200)
    end
  end
end
