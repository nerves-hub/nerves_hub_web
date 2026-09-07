defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices.Certificates

  describe "certificates" do
    test "download certificate for device", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      [cert | _] = Certificates.get_device_certificates(device)

      conn = get(conn, ~p"/org/#{org}/#{product}/devices/#{device}/certificate/#{cert.serial}/download")

      [str] = Plug.Conn.get_resp_header(conn, "content-disposition")

      assert str =~ "attachment; filename"
      assert conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end
end
