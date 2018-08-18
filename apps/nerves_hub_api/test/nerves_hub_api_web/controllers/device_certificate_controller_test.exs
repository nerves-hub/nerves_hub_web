defmodule NervesHubAPIWeb.DeviceCertificateControllerTest do
  use NervesHubAPIWeb.ConnCase

  alias NervesHubCore.{Devices, Certificate}
  alias NervesHubCore.Fixtures

  setup context do
    org = context.org
    identifier = "device-1234"
    device = %{identifier: identifier, description: "test device", tags: ["test"], org_id: org.id}
    {:ok, device} = Devices.create_device(device)
    {:ok, Map.put(context, :device, device)}
  end

  describe "index" do
    test "lists all certificates", %{device: device, conn: conn} do
      conn = get(conn, device_certificate_path(conn, :index, device.identifier))
      assert json_response(conn, 200)["data"] == []
    end
  end

  @tag :ca_integration
  describe "create device certificate" do
    test "renders key when data is valid", %{device: device, conn: conn} do
      csr =
        Fixtures.path()
        |> Path.join("cfssl/device-1234-csr.pem")
        |> File.read!()
        |> Base.encode64()

      params = %{identifier: device.identifier, csr: csr}

      conn = post(conn, device_certificate_path(conn, :sign, device.identifier), params)
      resp_data = json_response(conn, 200)["data"]
      assert %{"cert" => cert} = resp_data

      {:ok, serial} = Certificate.get_serial_number(cert)
      {:ok, cert} = Devices.get_device_certificate_by_serial(serial)

      assert cert.device_id == device.id
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, key_path(conn, :create))
      assert json_response(conn, 422)["errors"] != %{}
    end
  end
end
