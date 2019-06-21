defmodule NervesHubAPIWeb.DeviceCertificateControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubWebCore.Devices

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
          device_certificate_path(conn, :index, org.name, product.name, device.identifier)
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
          device_certificate_path(conn, :sign, org.name, product.name, device.identifier),
          params
        )

      resp_data = json_response(conn, 200)["data"]
      assert %{"cert" => cert} = resp_data

      cert = X509.Certificate.from_pem!(cert)
      {:ok, cert} = Devices.get_device_certificate_by_x509(cert)

      assert cert.device_id == device.id
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
          device_certificate_path(conn, :sign, org.name, product.name, device.identifier),
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
end
