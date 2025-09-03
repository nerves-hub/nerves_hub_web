defmodule NervesHubWeb.DeviceControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Fixtures

  setup %{org: org, user: user} do
    [product: Fixtures.product_fixture(user, org)]
  end

  describe "console" do
    test "shows information about device", %{conn: conn, org: org, product: product, user: user} do
      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/console")
      |> assert_has("p", text: "Console")
      |> assert_has("p", text: "Chat")
    end
  end

  describe "certificates" do
    test "download certificate for device", %{
      conn: conn,
      device: device,
      org: org,
      product: product
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
