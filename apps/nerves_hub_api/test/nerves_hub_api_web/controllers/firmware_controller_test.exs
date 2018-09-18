defmodule NervesHubAPIWeb.FirmwareControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Support.Fwup
  alias NervesHubCore.Firmwares
  alias NervesHubCore.Accounts
  alias NervesHubCore.Firmwares.Firmware

  describe "index" do
    test "lists all firmwares", %{conn: conn, org: org, product: product} do
      path = firmware_path(conn, :index, org.name, product.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create firmware" do
    test "renders firmware when data is valid", %{org: org, product: product} do
      org_key = Fixtures.org_key_fixture(org)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      {:ok, metadata} = Firmwares.extract_metadata(signed_firmware_path)
      uuid = Firmware.get_metadata_item(metadata, "meta-uuid")

      body = File.read!(signed_firmware_path)
      length = byte_size(body)

      conn =
        build_auth_conn()
        |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_req_header("content-length", "#{length}")

      path = firmware_path(conn, :create, org.name, product.name)
      conn = post(conn, path, body)
      assert json_response(conn, 201)["data"]

      conn = get(conn, firmware_path(conn, :show, org.name, product.name, uuid))
      assert json_response(conn, 200)["data"]["uuid"] == uuid
    end

    test "renders error when size limit is exceeded", %{org: org, product: product} do
      Accounts.create_org_limit(%{org_id: org.id, firmware_size: 1})

      %{name: "test", key: File.read!(@fw_key_path), org_id: org.id}
      |> NervesHubCore.Accounts.create_org_key()

      body = File.read!(@signed_firmware_path)
      length = byte_size(body)

      conn =
        build_auth_conn()
        |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_req_header("content-length", "#{length}")

      path = firmware_path(conn, :create, org.name, product.name)
      conn = post(conn, path, body)
      assert json_response(conn, 500)["errors"] =~ "exceeds size limit"
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, product: product} do
      conn = post(conn, firmware_path(conn, :create, org.name, product.name))
      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "delete firmware" do
    setup [:create_firmware]

    test "deletes chosen firmware", %{conn: conn, org: org, product: product, firmware: firmware} do
      conn = delete(conn, firmware_path(conn, :delete, org.name, product.name, firmware.uuid))
      assert response(conn, 204)

      conn = get(conn, firmware_path(conn, :show, org.name, product.name, firmware.uuid))

      assert response(conn, 404)
    end
  end

  defp create_firmware(%{org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    {:ok, %{firmware: firmware}}
  end
end
