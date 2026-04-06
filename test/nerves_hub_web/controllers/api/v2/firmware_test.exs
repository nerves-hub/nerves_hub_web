defmodule NervesHubWeb.API.V2.FirmwareTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    [firmware: firmware, org_key: org_key]
  end

  describe "index" do
    test "lists firmwares", %{conn: conn, firmware: firmware} do
      conn = get(conn, "/api/v2/firmwares")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      uuids = Enum.map(resp["data"], & &1["attributes"]["uuid"])
      assert firmware.uuid in uuids
    end
  end

  describe "show" do
    test "returns a firmware by id", %{conn: conn, firmware: firmware} do
      conn = get(conn, "/api/v2/firmwares/#{firmware.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["uuid"] == firmware.uuid
    end
  end

  describe "list_by_product" do
    test "lists firmwares by product", %{conn: conn, firmware: firmware} do
      conn = get(conn, "/api/v2/firmwares/by-product/#{firmware.product_id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      uuids = Enum.map(resp["data"], & &1["attributes"]["uuid"])
      assert firmware.uuid in uuids
    end
  end

  describe "list_by_org" do
    test "lists firmwares by org", %{conn: conn, org: org, firmware: firmware} do
      conn = get(conn, "/api/v2/firmwares/by-org/#{org.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      uuids = Enum.map(resp["data"], & &1["attributes"]["uuid"])
      assert firmware.uuid in uuids
    end
  end

  describe "get_by_product_and_uuid" do
    test "returns a firmware by product and uuid", %{conn: conn, firmware: firmware} do
      conn = get(conn, "/api/v2/firmwares/by-product/#{firmware.product_id}/uuid/#{firmware.uuid}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["uuid"] == firmware.uuid
    end
  end

  describe "delete" do
    test "deletes a firmware", %{conn: conn, firmware: firmware} do
      conn = delete(conn, "/api/v2/firmwares/#{firmware.id}")
      assert response(conn, 200)
    end
  end
end
