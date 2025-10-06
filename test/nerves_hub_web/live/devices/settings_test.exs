defmodule NervesHubWeb.Live.Devices.SettingsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices
  alias NervesHub.Repo
  alias NervesHubWeb.Components.Utils

  describe "device settings" do
    test "can change tags", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "General settings")
      |> fill_in("Tags", with: "josh, lars")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "Device updated")
      |> click_link("Details")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
      |> assert_has("span", text: "josh")
      |> assert_has("span", text: "lars")
    end

    test "can add 'first connect code'", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "General settings")
      |> fill_in("First connect code", with: "dbg(\"boo\")")
      |> click_button("Save changes")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      |> assert_has("div", text: "Device updated")

      device = Devices.get_device(device.id)

      assert device.connecting_code == "dbg(\"boo\")"
    end
  end

  describe "device certificates" do
    test "can upload certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      conn =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
        # Device has 1 certificate as default
        |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
        |> upload("Upload certificate", "test/fixtures/ssl/device-test-cert.pem")
        |> assert_has("div", text: "Certificate Upload Successful")
        |> assert_path("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")

      device = Repo.preload(device, :device_certificates, force: true)

      assert Enum.count(device.device_certificates) == 2

      Enum.each(device.device_certificates, fn cert ->
        assert_has(conn, "div", text: "Serial: #{Utils.format_serial(cert.serial)}")
      end)
    end

    test "can delete certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
      # Device has 1 certificate as default
      |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
      |> click_button("button[phx-click=\"delete-certificate\"]", "")
      |> refute_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")

      device = Repo.preload(device, :device_certificates, force: true)

      assert Enum.empty?(device.device_certificates)
    end

    test "can download certificate", %{conn: conn, org: org, product: product, device: device} do
      device = Repo.preload(device, :device_certificates)

      cert = device.device_certificates |> List.first()

      result =
        conn
        |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settings")
        # Device has 1 certificate as default
        |> assert_has("div", text: "Serial: #{Utils.format_serial(cert.serial)}")
        |> click_link("a[download=\"\"]", "")

      assert result.conn.resp_body =~ "-----BEGIN CERTIFICATE-----"
    end
  end
end
