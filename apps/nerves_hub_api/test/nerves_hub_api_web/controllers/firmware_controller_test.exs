defmodule NervesHubAPIWeb.FirmwareControllerTest do
  use NervesHubAPIWeb.ConnCase

  alias NervesHubCore.Fixtures
  alias NervesHubCore.Firmwares
  alias NervesHubCore.Firmwares.Firmware

  @test_firmware_path Path.expand("../../../../../test/fixtures/firmware", __DIR__)
  @signed_firmware_path Path.join(@test_firmware_path, "signed-key1.fw")
  @fw_key_path Path.join(@test_firmware_path, "fwup-key1.pub")

  describe "index" do
    test "lists all firmwares", %{conn: conn, product: product} do
      qp = URI.encode_query(%{product_name: product.name})
      path = firmware_path(conn, :index) <> "?" <> qp
      conn = get(conn, path)
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create firmware" do
    test "renders firmware when data is valid", %{org: org} do
      %{name: "test", key: File.read!(@fw_key_path), org_id: org.id}
      |> NervesHubCore.Accounts.create_org_key()

      {:ok, metadata} = Firmwares.extract_metadata(@signed_firmware_path)
      uuid = Firmware.get_metadata_item(metadata, "meta-uuid")

      body = File.read!(@signed_firmware_path)
      length = byte_size(body)

      conn =
        build_auth_conn()
        |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_req_header("content-length", "#{length}")

      path = firmware_path(conn, :create)
      conn = post(conn, path, body)
      assert json_response(conn, 201)["data"]

      conn = get(conn, firmware_path(conn, :show, uuid))
      assert json_response(conn, 200)["data"]["uuid"] == uuid
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, firmware_path(conn, :create))
      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "delete firmware" do
    setup [:create_firmware]

    test "deletes chosen firmware", %{conn: conn, firmware: firmware} do
      conn = delete(conn, firmware_path(conn, :delete, firmware.uuid))
      assert response(conn, 204)

      conn = get(conn, firmware_path(conn, :show, firmware.uuid))

      assert response(conn, 404)
    end
  end

  defp create_firmware(%{org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    {:ok, %{firmware: firmware}}
  end
end
