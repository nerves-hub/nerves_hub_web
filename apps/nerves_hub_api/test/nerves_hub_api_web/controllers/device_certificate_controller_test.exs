defmodule NervesHubAPIWeb.DeviceCertificateControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.{Devices, Fixtures}

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

    test "renders error when using deprecated api", %{conn: conn, org: org} do
      conn = get(conn, "/orgs/#{org.name}/devices/1234/certificates")
      {:error, reason} = NervesHubAPIWeb.DeviceController.error_deprecated(conn, %{})
      assert json_response(conn, 500)["errors"] == reason
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

      assert db_cert.der == X509.Certificate.to_der(otp_certificate)
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

  describe "sign device certificate" do
    @tag :ca_integration
    test "renders key when data is valid", %{
      conn: conn,
      org: org,
      device: device,
      product: product
    } do
      subject = "/O=NervesHub/CN=device-1234"
      key = X509.PrivateKey.new_ec(:secp256r1)

      csr =
        X509.CSR.new(key, subject)
        |> X509.CSR.to_pem()
        |> Base.encode64()

      params = %{identifier: device.identifier, csr: csr}

      conn =
        post(
          conn,
          Routes.device_certificate_path(conn, :sign, org.name, product.name, device.identifier),
          params
        )

      resp_data = json_response(conn, 200)["data"]
      assert %{"cert" => cert} = resp_data

      otp_cert = X509.Certificate.from_pem!(cert)
      {:ok, db_cert} = Devices.get_device_certificate_by_x509(cert)

      assert db_cert.device_id == device.id
      assert db_cert.der == X509.Certificate.to_der(otp_cert)
    end

    @tag :ca_integration
    test "renders errors when data is invalid", %{
      conn: conn,
      org: org,
      device: device,
      product: product
    } do
      conn =
        post(
          conn,
          Routes.device_certificate_path(conn, :sign, org.name, product.name, device.identifier),
          csr: ""
        )

      assert json_response(conn, 500)["errors"] != %{}
    end

    test "renders error when using deprecated api", %{conn: conn, org: org} do
      conn = post(conn, "/orgs/#{org.name}/devices/1234/certificates/sign", %{})
      {:error, reason} = NervesHubAPIWeb.DeviceController.error_deprecated(conn, %{})
      assert json_response(conn, 500)["errors"] == reason
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
