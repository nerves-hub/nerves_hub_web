defmodule NervesHubWeb.Live.Devices.NewTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  describe "new device" do
    test "requires an identifier", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/new")
      |> assert_has("h1", text: "Add Device")
      |> click_button("Add Device")
      |> assert_path("/org/#{org.name}/#{product.name}/devices/new")
      |> assert_has("div", text: "Failed to add device.")
      |> assert_has(".help-block", text: "can't be blank")
    end

    test "creates a device with just an identifier", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/new")
      |> assert_has("h1", text: "Add Device")
      |> fill_in("ID", with: "aaabbbccc111222333")
      |> click_button("Add Device")
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "Device created successfully.")
      |> assert_has("a", text: "aaabbbccc111222333")
    end

    test "creates a device with an identifier and tags", %{conn: conn, org: org, product: product} do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/new")
      |> assert_has("h1", text: "Add Device")
      |> fill_in("ID", with: "aaabbbccc111222333")
      |> fill_in("Tags", with: "josh, lars")
      |> click_button("Add Device")
      |> assert_path("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "Device created successfully.")
      |> assert_has("span", text: "josh")
      |> assert_has("span", text: "lars")
    end
  end
end
