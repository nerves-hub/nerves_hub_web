defmodule NervesHubWeb.API.DeviceCertificateControllerTest do
  use NervesHubWeb.APIConnCase, async: true

  alias NervesHub.{Certificate, Devices, Fixtures}

  setup %{org: org, product: product} do
    identifier = "device-1234"

    device = %{
      identifier: identifier,
      description: "test device",
      tags: ["test"],
      org_id: org.id,
      product_id: product.id
    }

    {:ok, device} = Devices.create_device(device)
    [device: device]
  end

  describe "index" do
    test "lists all certificates", %{conn: conn, org: org, product: product, device: device} do
      conn =
        get(
          conn,
          Routes.device_certificate_path(conn, :index, org.name, product.name, device.identifier)
        )

      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create device certificate" do
    test "renders cert when data is valid", %{
      conn: conn,
      org: org,
      device: device,
      product: product
    } do
      pem = Fixtures.device_certificate_pem()
      encoded_pem = Base.encode64(pem)

      conn =
        post(
          conn,
          Routes.device_certificate_path(
            conn,
            :create,
            org.name,
            product.name,
            device.identifier
          ),
          %{"cert" => encoded_pem}
        )

      resp = json_response(conn, 201)
      assert serial = resp["data"]["serial"]

      conn =
        get(
          conn,
          Routes.device_certificate_path(
            conn,
            :show,
            org.name,
            product.name,
            device.identifier,
            serial
          )
        )

      assert json_response(conn, 200)["data"]["serial"] == serial

      otp_certificate = X509.Certificate.from_pem!(pem)
      {:ok, db_cert} = Devices.get_device_certificate_by_x509(otp_certificate)

      assert db_cert.der == Certificate.to_der(otp_certificate)
      assert db_cert.fingerprint == Certificate.fingerprint(otp_certificate)
      assert db_cert.public_key_fingerprint == Certificate.public_key_fingerprint(otp_certificate)
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      org: org,
      device: device,
      product: product
    } do
      conn =
        post(
          conn,
          Routes.device_certificate_path(
            conn,
            :create,
            org.name,
            product.name,
            device.identifier
          ),
          cert: ""
        )

      assert json_response(conn, 500)["errors"] != %{}
    end
  end

  describe "delete device_certificate" do
    test "deletes chosen ca_certificate", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      %{db_cert: cert} = Fixtures.device_certificate_fixture(device)

      conn =
        delete(
          conn,
          Routes.device_certificate_path(
            conn,
            :delete,
            org.name,
            product.name,
            device.identifier,
            cert.serial
          )
        )

      assert response(conn, 204)

      conn =
        get(
          conn,
          Routes.device_certificate_path(
            conn,
            :show,
            org.name,
            product.name,
            device.identifier,
            cert.serial
          )
        )

      assert response(conn, 404)
    end
  end
end
