defmodule NervesHubAPIWeb.DeviceCertificateControllerTest do
  use NervesHubAPIWeb.ConnCase, async: true

  alias NervesHubCore.{Devices, Certificate}

  setup context do
    org = context.org
    identifier = "device-1234"
    device = %{identifier: identifier, description: "test device", tags: ["test"], org_id: org.id}
    {:ok, device} = Devices.create_device(device)
    {:ok, Map.put(context, :device, device)}
  end

  describe "index" do
    test "lists all certificates", %{conn: conn, org: org, device: device} do
      conn = get(conn, device_certificate_path(conn, :index, org.name, device.identifier))
      assert json_response(conn, 200)["data"] == []
    end
  end

  describe "create device certificate" do
    @tag :ca_integration
    test "renders key when data is valid", %{conn: conn, org: org, device: device} do
      subject = "/O=NervesHub/CN=device-1234"
      key = X509.PrivateKey.new_ec(:secp256r1)

      csr =
        X509.CSR.new(key, subject)
        |> X509.CSR.to_pem()
        |> Base.encode64()

      params = %{identifier: device.identifier, csr: csr}

      conn = post(conn, device_certificate_path(conn, :sign, org.name, device.identifier), params)
      resp_data = json_response(conn, 200)["data"]
      assert %{"cert" => cert} = resp_data

      cert = X509.Certificate.from_pem!(cert)
      serial = Certificate.get_serial_number(cert)
      {:ok, cert} = Devices.get_device_certificate_by_serial(serial)

      assert cert.device_id == device.id
    end

    @tag :ca_integration
    test "renders errors when data is invalid", %{conn: conn, org: org, device: device} do
      conn =
        post(conn, device_certificate_path(conn, :sign, org.name, device.identifier), csr: "")

      assert json_response(conn, 500)["errors"] != %{}
    end
  end
end
