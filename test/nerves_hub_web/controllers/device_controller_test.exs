defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  setup %{user: user, org: org} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "certificates" do
    test "download certificate for device", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      [cert | _] = NervesHub.Devices.get_device_certificates(device)

      conn =
        conn
        |> get("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/certificate/#{cert.serial}/download")

      [str] =
        Plug.Conn.get_resp_header(conn, "content-disposition")

      assert str =~ "attachment; filename"
      assert conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end
end
