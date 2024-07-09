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
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
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
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "Device updated")

      device = Devices.get_device(device.id)

      assert device.connecting_code == "dbg(\"boo\")"
    end
  end
end
