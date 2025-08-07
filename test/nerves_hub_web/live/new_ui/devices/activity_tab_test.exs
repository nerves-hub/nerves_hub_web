defmodule NervesHubWeb.Live.NewUI.Devices.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.AuditLogs.DeviceTemplates

  setup %{conn: conn} do
    [conn: init_test_session(conn, %{"new_ui" => true})]
  end

  test "no audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")
    |> assert_has("span", text: "No audit logs found for the device.")
  end

  test "audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device,
    user: user
  } do
    # Add audit log item for the device
    DeviceTemplates.audit_reboot(user, device)

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")
    |> assert_has("div", text: "User #{user.name} rebooted device #{device.identifier}")
  end

  describe "pagination" do
    test "pagination works with URL parameters", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      # Create multiple audit log entries for pagination testing (30 entries)
      Enum.each(1..30, fn i ->
        NervesHub.AuditLogs.audit!(
          user,
          device,
          "New UI test audit log entry #{i}"
        )
      end)

      # Test page 1 with default page_size=25
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")
      |> assert_has("div.flex.items-center.gap-6", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")

      # Test page 2 with page_size=25
      conn
      |> visit(
        "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity?page_number=2&page_size=25"
      )
      # Remaining 5 entries
      |> assert_has("div.flex.items-center.gap-6", count: 5)
      |> assert_has("button[phx-value-page=\"1\"]")

      # Test custom page_size=10
      conn
      |> visit(
        "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity?page_number=1&page_size=10"
      )
      |> assert_has("div.flex.items-center.gap-6", count: 10)
      |> assert_has("button[phx-value-page=\"2\"]")
      |> assert_has("button[phx-value-page=\"3\"]")
    end

    test "pagination events work correctly", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      # Create enough audit logs for pagination
      Enum.each(1..30, fn i ->
        NervesHub.AuditLogs.audit!(
          user,
          device,
          "New UI pagination test entry #{i}"
        )
      end)

      {:ok, view, _html} =
        live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")

      # Test paginate event
      view
      |> element("button[phx-click=\"paginate\"][phx-value-page=\"2\"]", "2")
      |> render_click()

      # Should redirect to page 2 on activity page
      assert_patch(
        view,
        "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity?page_number=2&page_size=25"
      )
    end

    test "page size selection works correctly", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      # Create 60 audit logs for testing page size changes
      Enum.each(1..60, fn i ->
        NervesHub.AuditLogs.audit!(
          user,
          device,
          "Page size test entry #{i}"
        )
      end)

      {:ok, view, _html} =
        live(conn, "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity")

      # Test changing page size to 50
      view
      |> element("button[phx-click=\"set-paginate-opts\"][phx-value-page-size=\"50\"]")
      |> render_click()

      # Should redirect to page 1 with page_size=50
      assert_patch(
        view,
        "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/activity?page_number=1&page_size=50"
      )
    end
  end
end
