defmodule NervesHubWeb.Live.Devices.Show.FirmwareHistoryTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Devices.DeviceFirmwares

  test "no firmware history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/firmware_history")
    |> assert_has("span", text: "No firmware history found for the device.")
  end

  test "audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    metadata = Map.from_struct(device.firmware_metadata)

    {:ok, df1} = DeviceFirmwares.add_reported_firmware(device, metadata, :validated, false)

    metadata = %{metadata | uuid: "abc", version: "0.2.0"}

    {:ok, df2} = DeviceFirmwares.add_reported_firmware(device, metadata, :validated, false)

    conn
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/firmware_history")
    |> assert_has("#device-firmware-#{df1.id} div span", text: device.firmware_metadata.version)
    |> assert_has("#device-firmware-#{df1.id} div span", text: "Validated")
    |> assert_has("#device-firmware-#{df2.id} div span", text: "0.2.0")
    |> assert_has("#device-firmware-#{df2.id} div", text: "Firmware unrecognized")
  end

  describe "pagination" do
    test "pagination works with URL parameters", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # Create multiple device firmware entries for pagination testing (30 entries)
      Enum.each(1..30, fn i ->
        metadata = Map.from_struct(device.firmware_metadata)
        metadata = %{metadata | uuid: "uuid-#{i}"}
        {:ok, _} = DeviceFirmwares.add_reported_firmware(device, metadata, :validated, false)
      end)

      # Test page 1 with default page_size=25
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/firmware_history")
      |> assert_has("div.flex.items-center.gap-6", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")

      # Test page 2 with page_size=25
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?page_number=2&page_size=25")
      # Remaining 5 entries
      |> assert_has("div.flex.items-center.gap-6", count: 5)
      |> assert_has("button[phx-value-page=\"1\"]")

      # Test custom page_size=10
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?page_number=1&page_size=10")
      |> assert_has("div.flex.items-center.gap-6", count: 10)
      |> assert_has("button[phx-value-page=\"2\"]")
      |> assert_has("button[phx-value-page=\"3\"]")
    end

    test "pagination events work correctly", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # Create multiple device firmware entries for pagination testing (30 entries)
      Enum.each(1..30, fn i ->
        metadata = Map.from_struct(device.firmware_metadata)
        metadata = %{metadata | uuid: "uuid-#{i}"}
        {:ok, _} = DeviceFirmwares.add_reported_firmware(device, metadata, :validated, false)
      end)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history")

      # Test paginate event
      view
      |> element(~s(button[phx-click="paginate"][phx-value-page="2"]), "2")
      |> render_click()

      # Should redirect to page 2 on activity page
      assert_patch(
        view,
        ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?page_number=2&page_size=25"
      )
    end

    test "page size selection works correctly", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # Create multiple device firmware entries for pagination testing (60 entries)
      Enum.each(1..60, fn i ->
        metadata = Map.from_struct(device.firmware_metadata)
        metadata = %{metadata | uuid: "uuid-#{i}"}
        {:ok, _} = DeviceFirmwares.add_reported_firmware(device, metadata, :validated, false)
      end)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history")

      # Test changing page size to 50
      view
      |> element(~s(button[phx-click="set-paginate-opts"][phx-value-page-size="50"]))
      |> render_click()

      # Should redirect to page 1 with page_size=50
      assert_patch(
        view,
        ~p"/org/#{org}/#{product}/devices/#{device}/firmware_history?page_number=1&page_size=50"
      )
    end
  end
end
