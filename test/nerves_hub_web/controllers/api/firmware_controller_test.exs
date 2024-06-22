defmodule NervesHubWeb.API.FirmwareControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.Fixtures
  alias NervesHub.Support.Fwup

  describe "index" do
    test "lists all firmwares", %{conn: conn, org: org, product: product} do
      path = Routes.api_firmware_path(conn, :index, org.name, product.name)
      conn = get(conn, path)
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create firmware" do
    test "renders firmware when data is valid", %{
      conn: conn,
      user: user,
      org: org,
      product: product
    } do
      org_key = Fixtures.org_key_fixture(org, user)

      {:ok, signed_firmware_path} =
        Fwup.create_signed_firmware(org_key.name, "unsigned", "signed", %{product: product.name})

      upload = %Plug.Upload{
        path: signed_firmware_path,
        filename: "doesnt_matter.fw"
      }

      params = %{"firmware" => upload}
      path = Routes.api_firmware_path(conn, :create, org.name, product.name)
      conn = post(conn, path, params)
      assert data = json_response(conn, 201)["data"]
      uuid = data["uuid"]

      conn = get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, uuid))
      assert json_response(conn, 200)["data"]["uuid"] == uuid
    end

    test "renders errors when data is invalid", %{conn: conn, org: org, product: product} do
      conn = post(conn, Routes.api_firmware_path(conn, :create, org.name, product.name))
      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "delete firmware" do
    setup [:create_firmware]

    test "deletes chosen firmware", %{conn: conn, org: org, product: product, firmware: firmware} do
      conn =
        delete(
          conn,
          Routes.api_firmware_path(conn, :delete, org.name, product.name, firmware.uuid)
        )

      assert response(conn, 204)

      conn =
        get(conn, Routes.api_firmware_path(conn, :show, org.name, product.name, firmware.uuid))

      assert response(conn, 404)
    end

    test "firmware delete with associated deployment", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.deployment_fixture(org, firmware)

      conn =
        delete(
          conn,
          Routes.api_firmware_path(conn, :delete, org.name, product.name, firmware.uuid)
        )

      assert response(conn, 409)
    end
  end

  defp create_firmware(%{user: user, org: org, product: product}) do
    org_key = Fixtures.org_key_fixture(org, user)
    firmware = Fixtures.firmware_fixture(org_key, product)
    {:ok, %{firmware: firmware}}
  end
end
