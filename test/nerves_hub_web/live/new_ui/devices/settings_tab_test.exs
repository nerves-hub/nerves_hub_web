defmodule NervesHubWeb.NewUi.Devices.SettingsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Devices
  alias NervesHubWeb.Components.Utils

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

    test "upload certificate", %{conn: conn, org: org, product: product, device: device} do
      cert_path = "test/fixtures/ssl/device-test-cert.pem"

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> click_button("Upload certificate")
      |> unwrap(fn view ->
        file_input(view, "form", :certificate, [
          %{name: "device-test-cert.pem", content: File.read!(cert_path)}
        ])
        |> render_upload("device-test-cert.pem")
        |> render()
      end)
      |> assert_has("div", text: "Certificate Upload Successful")
      |> assert_has("div", text: "Serial:")
    end

    test "delete certificate", %{conn: conn, org: org, product: product, device: device} do
      [certificate] = Devices.get_device_certificates(device)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> assert_has("div", text: "Serial: #{Utils.format_serial(certificate.serial)}")
      |> click_button("Delete")
      |> assert_has("div", text: "Certificate deleted.")
      |> refute_has("div", text: "Serial: #{Utils.format_serial(certificate.serial)}")
    end
  end

  describe "device settings" do
    test "update description, tags, and first connect code", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> fill_in("Description", with: "Test device description")
      |> fill_in("Tags", with: "alpha, beta")
      |> fill_in("First connect code", with: "IO.puts(\"hello\")")
      |> click_button("Save changes")
      |> assert_has("div", text: "Device updated.")

      # Optionally, reload device and assert values
      updated = Devices.get_device(device.id)
      assert updated.description == "Test device description"
      assert Enum.sort(updated.tags) == ["alpha", "beta"]
      assert updated.connecting_code == "IO.puts(\"hello\")"
    end
  end

  describe "extensions" do
    test "toggle extension", %{conn: conn, org: org, product: product, device: device} do
      # Assume at least one extension exists
      [ext | _] = Map.keys(device.product.extensions) |> Enum.filter(&(&1 != :__struct__))

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> assert_has("div", text: "Extensions")
      |> unwrap(fn view ->
        render_change(view, "update-extension", %{"extension" => ext, "value" => "on"})
      end)
      |> assert_has("div", text: "successfully enabled")
      |> unwrap(fn view ->
        render_change(view, "update-extension", %{"extension" => ext, "value" => "off"})
      end)
      |> assert_has("div", text: "successfully disabled")
    end
  end

  describe "delete device" do
    test "delete device", %{conn: conn, org: org, product: product, device: device} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/settingz")
      |> click_button("Delete device")
      |> assert_has("div", text: "The device has been deleted. This action can be undone.")

      # Optionally, check device is marked deleted
      deleted = Devices.get_device(device.id)
      assert deleted.deleted_at != nil
    end
  end
end
