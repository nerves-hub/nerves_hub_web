defmodule NervesHubWeb.Live.Devices.Show.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices.Updates
  alias NervesHubWeb.Components.DevicePage.ActivityTab

  test "no audit log history exists for the device", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    conn
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
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
    |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
    |> assert_has("div", text: "User #{user.name} rebooted device #{device.identifier}")
  end

  describe "icons" do
    test "each entry shows the icon for its kind", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      DeviceTemplates.audit_reboot(user, device)
      DeviceTemplates.audit_firmware_validated(device)
      DeviceTemplates.audit_firmware_metadata_updated(device)
      {:ok, _} = Updates.enable_updates(device, user)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("div.flex.items-center.gap-6:has(span.lucide-power)", text: "rebooted device")
      |> assert_has("div.flex.items-center.gap-6:has(span.lucide-shield-check)", text: "has validated its firmware")
      |> assert_has("div.flex.items-center.gap-6:has(span.lucide-file-text)", text: "updated firmware metadata")
      |> assert_has("div.flex.items-center.gap-6:has(span.lucide-toggle-right)", text: "enabled updates")
      |> refute_has("span.lucide-activity")
    end

    test "an entry with no kind, as older ones have, gets a neutral icon", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      :ok = AuditLogs.audit!(user, device, "Written before entries had kinds")

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("div.flex.items-center.gap-6:has(span.lucide-activity)", text: "Written before entries had kinds")
    end

    test "every kind has an icon of its own" do
      for kind <- AuditLog.kinds() do
        refute ActivityTab.kind_icon(kind) == ActivityTab.kind_icon(nil), "#{kind} has no icon"
      end
    end

    test "the icons are the ones the Paper boards draw" do
      assert ActivityTab.kind_icon(:device_rebooted) == "lucide-power"
      assert ActivityTab.kind_icon(:firmware_validated) == "lucide-shield-check"
      assert ActivityTab.kind_icon(:firmware_updated) == "lucide-refresh-cw"
      assert ActivityTab.kind_icon(:firmware_metadata_updated) == "lucide-file-text"
      assert ActivityTab.kind_icon(:deployment_update_sent) == "lucide-download"
      assert ActivityTab.kind_icon(:updates_enabled) == "lucide-toggle-right"
    end
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
        NervesHub.AuditLogs.audit!(user, device, "New UI test audit log entry #{i}")
      end)

      # Test page 1 with default page_size=25
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("div.flex.items-center.gap-6", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")

      # Test page 2 with page_size=25
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=2&page_size=25")
      # Remaining 5 entries
      |> assert_has("div.flex.items-center.gap-6", count: 5)
      |> assert_has("button[phx-value-page=\"1\"]")

      # Test custom page_size=10
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=1&page_size=10")
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
        NervesHub.AuditLogs.audit!(user, device, "New UI pagination test entry #{i}")
      end)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices/#{device}/activity")

      # Test paginate event
      view
      |> element(~s(button[phx-click="paginate"][phx-value-page="2"]), "2")
      |> render_click()

      # Should redirect to page 2 on activity page
      assert_patch(
        view,
        ~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=2&page_size=25"
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
        NervesHub.AuditLogs.audit!(user, device, "Page size test entry #{i}")
      end)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices/#{device}/activity")

      # Test changing page size to 50
      view
      |> element(~s(button[phx-click="set-paginate-opts"][phx-value-page-size="50"]))
      |> render_click()

      # Should redirect to page 1 with page_size=50
      assert_patch(
        view,
        ~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=1&page_size=50"
      )
    end
  end
end
