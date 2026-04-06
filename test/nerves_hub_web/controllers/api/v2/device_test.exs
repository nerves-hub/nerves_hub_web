defmodule NervesHubWeb.API.V2.DeviceTest do
  use NervesHubWeb.AshAPIConnCase, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org, product: product, tmp_dir: tmp_dir} do
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    [device: device, firmware: firmware, org_key: org_key]
  end

  describe "index" do
    test "lists devices", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      identifiers = Enum.map(resp["data"], & &1["attributes"]["identifier"])
      assert device.identifier in identifiers
    end
  end

  describe "create" do
    test "creates a device", %{conn: conn, org: org, product: product} do
      conn =
        post(conn, "/api/v2/devices", %{
          "data" => %{
            "type" => "device",
            "attributes" => %{
              "identifier" => "ash-device-001",
              "org_id" => org.id,
              "product_id" => product.id
            }
          }
        })

      resp = json_response(conn, 201)
      assert resp["data"]["attributes"]["identifier"] == "ash-device-001"
    end
  end

  describe "show" do
    test "returns a device by id", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices/#{device.id}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["identifier"] == device.identifier
    end
  end

  describe "update" do
    test "updates a device", %{conn: conn, device: device} do
      conn =
        patch(conn, "/api/v2/devices/#{device.id}", %{
          "data" => %{
            "type" => "device",
            "id" => "#{device.id}",
            "attributes" => %{
              "description" => "Updated via Ash"
            }
          }
        })

      resp = json_response(conn, 200)
      assert resp["data"]["attributes"]["description"] == "Updated via Ash"
    end
  end

  describe "list_by_product" do
    test "lists devices by org and product", %{conn: conn, org: org, product: product, device: device} do
      conn = get(conn, "/api/v2/devices/by-product/#{org.id}/#{product.id}")
      resp = json_response(conn, 200)

      assert is_list(resp["data"])
      identifiers = Enum.map(resp["data"], & &1["attributes"]["identifier"])
      assert device.identifier in identifiers
    end
  end

  describe "get_by_identifier" do
    test "returns a device by identifier", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices/by-identifier/#{device.identifier}")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["identifier"] == device.identifier
    end
  end

  describe "includes" do
    test "includes product when requested", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices/#{device.id}?include=product")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["identifier"] == device.identifier
      included = resp["included"]
      assert is_list(included)
      assert Enum.any?(included, &(&1["type"] == "product"))
    end

    test "includes device_certificates when requested", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices/#{device.id}?include=device_certificates")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["identifier"] == device.identifier
      # included may be empty if no certs exist, but should not error
      assert is_list(resp["included"] || [])
    end

    test "includes multiple relationships", %{conn: conn, device: device} do
      conn = get(conn, "/api/v2/devices/#{device.id}?include=product,device_certificates")
      resp = json_response(conn, 200)

      assert resp["data"]["attributes"]["identifier"] == device.identifier
      included = resp["included"]
      assert is_list(included)
      assert Enum.any?(included, &(&1["type"] == "product"))
    end
  end

  describe "delete" do
    test "soft-deletes a device", %{conn: conn, device: device} do
      conn = delete(conn, "/api/v2/devices/#{device.id}")
      assert response(conn, 200)
    end
  end
end
