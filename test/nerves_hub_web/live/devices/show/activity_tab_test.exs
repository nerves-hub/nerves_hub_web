defmodule NervesHubWeb.Live.Devices.Show.ActivityTabTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.AuditLog
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices.Updates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
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
    |> assert_has("li[data-activity-entry]", text: "#{user.name} rebooted device #{device.identifier}")
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
      |> assert_has("li[data-activity-entry]:has(span.lucide-power--bold)", text: "rebooted device")
      |> assert_has("li[data-activity-entry]:has(span.lucide-shield-check--bold)", text: "has validated its firmware")
      |> assert_has("li[data-activity-entry]:has(span.lucide-file-text--bold)", text: "updated firmware metadata")
      |> assert_has("li[data-activity-entry]:has(span.lucide-toggle-right--bold)", text: "enabled updates")
      |> refute_has("span.lucide-activity--bold")
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
      |> assert_has("li[data-activity-entry]:has(span.lucide-activity--bold)", text: "Written before entries had kinds")
    end

    test "every kind has an icon other than the neutral one" do
      for kind <- AuditLog.kinds() do
        refute ActivityTab.kind_icon(kind) == ActivityTab.kind_icon(nil), "#{kind} has no icon"
      end
    end

    test "the icons are the ones the Paper boards draw" do
      assert ActivityTab.kind_icon(:device_rebooted) == "lucide-power--bold"
      assert ActivityTab.kind_icon(:firmware_validated) == "lucide-shield-check--bold"
      assert ActivityTab.kind_icon(:firmware_updated) == "lucide-refresh-cw--bold"
      assert ActivityTab.kind_icon(:firmware_metadata_updated) == "lucide-file-text--bold"
      assert ActivityTab.kind_icon(:deployment_update_sent) == "lucide-download--bold"
      assert ActivityTab.kind_icon(:updates_enabled) == "lucide-toggle-right--bold"
    end
  end

  describe "names and links" do
    test "names a user as they are now, after a rename", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      DeviceTemplates.audit_reboot(user, device)
      Repo.update!(Ecto.Changeset.change(user, name: "Renamed"))

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("li[data-activity-entry]", text: "Renamed rebooted device #{device.identifier}")
      |> refute_has("li[data-activity-entry]", text: "#{user.name} rebooted")
    end

    test "links the deployment group and firmware, under the group's current name", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: group,
      firmware: firmware
    } do
      DeviceTemplates.audit_device_deployment_group_update_triggered(device, group, firmware)
      group = Repo.update!(Ecto.Changeset.change(group, name: "Renamed-group"))

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has(
        ~s(li[data-activity-entry] a[href="/org/#{org.name}/#{product.name}/deployment_groups/#{group.name}"]),
        text: "Renamed-group"
      )
      |> assert_has(~s(li[data-activity-entry] a[href="/org/#{org.name}/#{product.name}/firmware/#{firmware.uuid}"]),
        text: firmware.uuid
      )
    end

    test "sets each reference apart and says what it is, linked or not", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      deployment_group: group,
      user: user
    } do
      DeviceTemplates.audit_device_deployment_group_update(user, device, group)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has(~s(li[data-activity-entry] span[data-ref="user"]), text: user.name)
      |> assert_has(~s(li[data-activity-entry] span[data-ref="device"]), text: device.identifier)
      |> assert_has(~s(li[data-activity-entry] a[data-ref="deployment_group"]), text: group.name)
      |> refute_has("li[data-activity-entry]", text: "User #{user.name}")
    end

    test "doesn't link the device to its own page", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      user: user
    } do
      DeviceTemplates.audit_reboot(user, device)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("li[data-activity-entry]", text: device.identifier)
      |> refute_has("li[data-activity-entry] a", text: device.identifier)
    end

    test "shows a reason a device sent as it is, placeholders and markup included", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      device = %{device | inflight_update: %{deployment_group: nil}}
      DeviceTemplates.audit_firmware_upgrade_failed(device, "%{actor} <b>bold</b>")

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("li[data-activity-entry]", text: ~s[("%{actor} <b>bold</b>")])
      |> refute_has("li[data-activity-entry] b")
    end

    test "a member limited to tagged devices sees the deployment group without a link", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware,
      deployment_group: group,
      user: user
    } do
      device = Fixtures.device_fixture(org, product, firmware, %{tags: ["support"]})
      DeviceTemplates.audit_device_deployment_group_update_triggered(device, group, firmware)

      role = Fixtures.org_role_fixture(org, %{device_tags: ["support"]})
      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, role)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity")
      |> assert_has("li[data-activity-entry]", text: "Deployment #{group.name} update triggered")
      |> refute_has("li[data-activity-entry] a")
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
      |> assert_has("li[data-activity-entry]", count: 25)
      |> assert_has("button[phx-value-page=\"2\"]")

      # Test page 2 with page_size=25
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=2&page_size=25")
      # Remaining 5 entries
      |> assert_has("li[data-activity-entry]", count: 5)
      |> assert_has("button[phx-value-page=\"1\"]")

      # Test custom page_size=10
      conn
      |> visit(~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=1&page_size=10")
      |> assert_has("li[data-activity-entry]", count: 10)
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
      |> form("#activity-pager-page-size", %{"page-size" => "50"})
      |> render_change()

      # Should redirect to page 1 with page_size=50
      assert_patch(
        view,
        ~p"/org/#{org}/#{product}/devices/#{device}/activity?page_number=1&page_size=50"
      )
    end
  end
end
