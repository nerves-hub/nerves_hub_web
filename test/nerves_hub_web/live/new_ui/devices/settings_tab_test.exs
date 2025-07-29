defmodule NervesHubWeb.NewUi.Devices.SettingsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHubWeb.Components.Utils
  alias NervesHub.Repo

  setup %{conn: conn} do
    [conn: init_test_session(conn, %{"new_ui" => true})]
  end

  describe "certificates" do
    test "download certificate", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      [certificate] = Devices.get_device_certificates(device)

      result =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
        |> assert_has("div", text: "Certificates")
        |> assert_has("div", text: "Serial: #{Utils.format_serial(certificate.serial)}")
        |> unwrap(fn view ->
          view
          |> element("a[download]")
          |> render_click()
        end)

      assert result.conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end

    test "delete certificate", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      [certificate] = Devices.get_device_certificates(device)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> click_button("[phx-click=\"delete-certificate\"]", "")

      refute Repo.reload(certificate)
    end
  end
end
