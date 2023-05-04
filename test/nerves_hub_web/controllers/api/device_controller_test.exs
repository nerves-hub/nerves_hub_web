defmodule NervesHubWeb.API.DeviceControllerTest do
  use NervesHubWeb.APIConnCase, async: false
  alias NervesHub.{Devices, Fixtures}

  describe "create devices" do
    test "renders device when data is valid", %{conn: conn, org: org, product: product} do
      identifier = "api-device-1234"

      device = %{
        identifier: identifier,
        description: "test device",
        tags: ["test"],
        updates_enabled: true
      }

      conn = post(conn, Routes.device_path(conn, :create, org.name, product.name), device)
      assert json_response(conn, 201)["data"]

      conn = get(conn, Routes.device_path(conn, :show, org.name, product.name, device.identifier))
      assert json_response(conn, 200)["data"]["identifier"] == identifier
      assert json_response(conn, 200)["data"]["updates_enabled"] == true
    end

    test "renders errors when data is invalid", %{conn: conn, org: org} do
      conn = post(conn, Routes.key_path(conn, :create, org.name))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "index" do
    test "lists all devices for an org", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)

      conn = get(conn, Routes.device_path(conn, :index, org.name, product.name))

      assert json_response(conn, 200)["data"]

      assert Enum.find(conn.assigns.devices, fn %{identifier: identifier} ->
               device.identifier == identifier
             end)
    end
  end

  describe "delete devices" do
    test "deletes chosen device", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, product, firmware)

      [to_delete | _] = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

      conn =
        delete(
          conn,
          Routes.device_path(conn, :delete, org.name, product.name, to_delete.identifier)
        )

      assert response(conn, 204)

      conn =
        get(conn, Routes.device_path(conn, :show, org.name, product.name, to_delete.identifier))

      assert json_response(conn, 200)["status"] != ""
    end
  end

  describe "update devices" do
    test "updates chosen device", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      Fixtures.device_fixture(org, product, firmware)

      [to_update | _] = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

      conn =
        put(
          conn,
          Routes.device_path(conn, :update, org.name, product.name, to_update.identifier),
          %{
            tags: ["a", "b", "c", "d"]
          }
        )

      assert json_response(conn, 201)["data"]

      conn =
        get(conn, Routes.device_path(conn, :show, org.name, product.name, to_update.identifier))

      assert json_response(conn, 200)
      assert conn.assigns.device.tags == ["a", "b", "c", "d"]
    end
  end

  describe "authenticate devices" do
    test "valid certificate", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org)
      org_key = Fixtures.org_key_fixture(org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      device = Fixtures.device_fixture(org, product, firmware)
      %{cert: ca, key: ca_key} = Fixtures.ca_certificate_fixture(org)

      cert =
        X509.PrivateKey.new_ec(:secp256r1)
        |> X509.PublicKey.derive()
        |> X509.Certificate.new("CN=#{device.identifier}", ca, ca_key)

      _device_certificate = Fixtures.device_certificate_fixture(device, cert)

      cert64 =
        cert
        |> X509.Certificate.to_pem()
        |> Base.encode64()

      conn =
        post(conn, Routes.device_path(conn, :auth, org.name, product.name), %{
          "certificate" => cert64
        })

      assert json_response(conn, 200)["data"]
    end
  end
end
