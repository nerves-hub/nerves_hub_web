defmodule NervesHubWeb.Live.Devices.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices

  describe "device settings" do
    test "can change tags", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("h1", text: "Device Settings")
      |> fill_in("Tags", with: "josh, lars")
      |> click_button("Save Changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div", text: "Device updated")
      |> assert_has("span", text: "josh")
      |> assert_has("span", text: "lars")
    end

    test "can add 'first connect code'", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("h1", text: "Device Settings")
      |> fill_in("First Connect Code", with: "dbg(\"boo\")")
      |> click_button("Save Changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("div", text: "Device updated")

      device = Devices.get_device(device.id)

      assert device.connecting_code == "dbg(\"boo\")"
    end
  end

  describe "device certificates" do
    test "can upload certificate", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      # Device has 1 certificate as default
      |> assert_has(".item", count: 1)
      |> click_button("#toggle-certificate-upload", "")
      |> unwrap(fn view ->
        file_input(view, ".import-pem", :certificate, [
          %{
            name: "device-test-cert.pem",
            content: File.read!("test/fixtures/ssl/device-test-cert.pem")
          }
        ])
        |> render_upload("device-test-cert.pem")

        render(view)
      end)
      |> assert_has("div", text: "Certificate Upload Successful")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has(".item", count: 2)
    end

    test "can delete certificate", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      # Device has 1 certificate as default
      |> assert_has(".item", count: 1)
      |> click_link("Delete")
      |> refute_has(".item")
    end

    test "can download certificate", %{conn: conn, org: org, product: product, device: device} do
      result =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
        # Device has 1 certificate as default
        |> assert_has(".item", count: 1)
        |> click_link("Download")

      assert result.conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end
end
