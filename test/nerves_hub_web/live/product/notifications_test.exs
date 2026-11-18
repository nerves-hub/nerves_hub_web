defmodule NervesHubWeb.Live.Product.NotificationsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Accounts.Scope
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ProductNotifications
  alias NervesHub.Products.Notification
  alias NervesHub.Repo

  defp page_path(org, product, query \\ ""), do: "/org/#{org.name}/#{product.name}/notifications#{query}"

  defp duplicate_identifier!(product, identifier) do
    ProductNotifications.create_duplicate_device_identifier_notification!(product.id, identifier, :shared_secrets)
  end

  # A notification that's a card of its own, told apart by the device it
  # names. Connecting code failures are raised per code, so they aren't
  # rolled up.
  defp code_failure!(product, identifier) do
    ProductNotifications.create_connecting_code_failure_notification!(
      %DeviceInfo{product_id: product.id, device_identifier: identifier},
      "code-#{identifier}",
      "boom"
    )
  end

  defp wrong_host!(product, identifier) do
    ProductNotifications.create_wrong_websocket_host_notification!(
      %DeviceInfo{product_id: product.id, device_identifier: identifier},
      "devices.example.com"
    )
  end

  @code_failure "A device could not run its connecting code."

  # Moves a notification back in time, so tests can put it in a day's group
  # or an order.
  defp last_occurred!(notification, seconds_ago) do
    at = DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)

    Notification
    |> Repo.get!(notification.id)
    |> Ecto.Changeset.change(last_occurred_at: at)
    |> Repo.update!()
  end

  # `count` cards, the first the most recent, a minute apart, about devices
  # "abc-01", "abc-02" and so on.
  defp many!(product, count) do
    for n <- 1..count do
      product |> code_failure!(identifier(n)) |> last_occurred!(n * 60)
    end
  end

  defp identifier(n), do: "abc-#{String.pad_leading(Integer.to_string(n), 2, "0")}"

  describe "the list" do
    test "shows each notification under the day it last happened, with its level and when", %{
      conn: conn,
      org: org,
      product: product
    } do
      _today = product |> code_failure!("today") |> last_occurred!(60)
      _old = product |> code_failure!("long-ago") |> last_occurred!(60 * 60 * 24 * 40)

      conn
      |> visit(page_path(org, product))
      |> assert_has("h1", text: "Notifications")
      |> assert_has("#level-all", text: "2")
      |> assert_has("#level-warning", text: "2")
      |> assert_has("#level-error", text: "0")
      |> assert_has("#day-today h2", text: "Today")
      |> assert_has("#day-today article", text: "today")
      |> refute_has("#day-today article", text: "long-ago")
      |> assert_has("article[data-level=warning]", text: "long-ago")
    end

    test "says when nothing needs attention", %{conn: conn, org: org, product: product} do
      conn
      |> visit(page_path(org, product))
      |> assert_has("#notifications-empty", text: "Nothing needs your attention")
      |> refute_has("#dismiss-all")
    end

    test "a level tab lists only that level, and says what the others hold when it's empty", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      _ = code_failure!(product, "abc")
      _ = ProductNotifications.create_update_mode_revert_failed_notification!(device)

      conn
      |> visit(page_path(org, product))
      |> click_link("#level-error", "Errors")
      |> assert_path(page_path(org, product), query_params: %{"level" => "error"})
      |> assert_has("article", text: "A device could not be returned to automatic updates.")
      |> refute_has("article", text: @code_failure)
      |> click_link("#level-info", "Info")
      |> assert_has("#notifications-level-empty", text: "No info notifications")
      |> assert_has("#notifications-level-empty", text: "There are 1 error and 1 warning.")
      |> click_link("Show all 2")
      |> assert_has("article", count: 2)
    end

    test "links a device it's about, and says when the device has gone", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware,
      user: user
    } do
      other_product = Fixtures.product_fixture(user, org)
      moved = Fixtures.device_fixture(org, other_product, firmware)
      deleted = Fixtures.device_fixture(org, product, firmware)
      {:ok, _} = Devices.delete_device(deleted)

      # Each of a different kind, so none are rolled up together.
      _ = ProductNotifications.create_missing_firmware_metadata_notification!(device)
      _ = code_failure!(product, moved.identifier)
      _ = ProductNotifications.create_update_mode_revert_failed_notification!(deleted)

      conn
      |> visit(page_path(org, product))
      |> assert_has("a[href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']", text: device.identifier)
      |> assert_has("article span", text: "#{moved.identifier} · moved")
      |> assert_has("article span", text: "#{deleted.identifier} · deleted")
      |> refute_has("a", text: moved.identifier)
    end

    test "a stopped workflow has no dismiss button, since it clears itself", %{
      conn: conn,
      org: org,
      product: product,
      deployment_group: deployment_group
    } do
      step = %DeploymentWorkflowStep{id: 1, number: 2, type: :approval_required}
      _ = ProductNotifications.create_workflow_halted_notification!(deployment_group, step, :awaiting_approval)

      conn
      |> visit(page_path(org, product))
      |> assert_has("article", text: "A deployment workflow is waiting for approval.")
      |> assert_has(
        "a[href='/org/#{org.name}/#{product.name}/deployment_groups/#{URI.encode(deployment_group.name, &URI.char_unreserved?/1)}']",
        text: deployment_group.name
      )
      |> assert_has("article", text: "Clears itself")
      |> refute_has("article button[phx-click=dismiss]")
    end
  end

  describe "dismissing" do
    test "one notification, which goes for everyone looking", %{conn: conn, org: org, product: product, user: user} do
      notification = code_failure!(product, "abc")
      _ = code_failure!(product, "def")

      conn
      |> visit(page_path(org, product))
      |> click_button("#notification-#{notification.id} button", "")
      |> assert_has("[role=alert]", text: "Dismissed “#{@code_failure}”")
      |> refute_has("article", text: "abc")
      |> assert_has("article", text: "def")
      |> assert_has("#level-all", text: "1")
      |> assert_has("#nav-notifications [data-count]", text: "1", exact: true)

      assert [%Notification{}] = Repo.all(Notification)

      assert {:error, :not_found} =
               Scope.for_user(user) |> Scope.put_product(product) |> ProductNotifications.dismiss(notification.id)
    end

    test "all of them, after asking, on every level", %{conn: conn, org: org, product: product, device: device} do
      _ = duplicate_identifier!(product, "abc")
      _ = ProductNotifications.create_update_mode_revert_failed_notification!(device)

      conn
      |> visit(page_path(org, product, "?level=error"))
      |> click_button("#dismiss-all", "Dismiss all")
      |> assert_has("#dismiss-all-dialog", text: "Dismiss all 2 notifications?")
      |> within("#dismiss-all-dialog", fn session -> click_button(session, "Dismiss all 2") end)
      |> assert_has("[role=alert]", text: "Dismissed all 2 notifications")
      |> assert_has("#notifications-empty")

      assert Repo.aggregate(Notification, :count) == 0
    end

    test "only the product being viewed", %{conn: conn, org: org, product: product, user: user} do
      other_product = Fixtures.product_fixture(user, org)
      _ = duplicate_identifier!(product, "abc")
      _ = duplicate_identifier!(other_product, "abc")

      conn
      |> visit(page_path(org, product))
      |> click_button("#dismiss-all", "Dismiss all")
      |> within("#dismiss-all-dialog", fn session -> click_button(session, "Dismiss 1") end)
      |> assert_has("#notifications-empty")

      assert [%Notification{product_id: other_product_id}] = Repo.all(Notification)
      assert other_product_id == other_product.id
    end

    test "says who, when someone else dismisses them all", %{conn: conn, org: org, product: product} do
      other_user = Fixtures.user_fixture()
      _ = Accounts.add_org_user(org, other_user, %{role: :manage})
      _ = duplicate_identifier!(product, "abc")

      conn
      |> visit(page_path(org, product))
      |> assert_has("article", text: "abc")
      |> tap(fn _ ->
        other_user |> Scope.for_user() |> Scope.put_product(product) |> ProductNotifications.delete_all()
      end)
      |> assert_has("#dismissed-by", text: "#{other_user.name} dismissed 1 notification.")
      |> assert_has("#notifications-empty")
    end

    test "isn't open to a member with the view role", %{conn: conn, org: org, product: product} do
      notification = duplicate_identifier!(product, "abc")
      Repo.update_all(OrgUser, set: [role: :view])

      conn =
        conn
        |> visit(page_path(org, product))
        |> assert_has("article", text: "abc")
        |> refute_has("#dismiss-all")
        |> refute_has("article button[phx-click=dismiss]")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "dismiss", %{"id" => notification.id}))

      assert Repo.aggregate(Notification, :count) == 1
    end

    test "isn't open to a member with the view role, all at once", %{conn: conn, org: org, product: product} do
      _ = duplicate_identifier!(product, "abc")
      Repo.update_all(OrgUser, set: [role: :view])

      conn = visit(conn, page_path(org, product))
      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} = catch_exit(render_click(conn.view, "dismiss-all", %{}))
      assert Repo.aggregate(Notification, :count) == 1
    end
  end

  describe "a problem on many devices" do
    setup %{org: org, product: product, firmware: firmware} do
      devices = for _ <- 1..3, do: Fixtures.device_fixture(org, product, firmware)
      notifications = for device <- devices, do: wrong_host!(product, device.identifier)

      %{devices: devices, notifications: notifications}
    end

    test "is one card that opens to its devices", %{conn: conn, org: org, product: product, devices: devices} do
      [device | _] = devices

      conn
      |> visit(page_path(org, product))
      |> assert_has("#level-all", text: "1")
      |> assert_has("#notification-wrong_websocket_host h3", text: "3 devices connected to the wrong host.")
      |> assert_has("#notification-wrong_websocket_host", text: "instead of devices.example.com")
      |> refute_has("#notification-wrong_websocket_host-devices")
      |> click_button("#notification-wrong_websocket_host button[aria-label='Show the 3 devices']", "")
      |> assert_has("#notification-wrong_websocket_host-devices li", count: 3)
      |> assert_has(
        "#notification-wrong_websocket_host-devices a[href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']",
        text: device.identifier
      )
      |> assert_has("#nav-notifications [data-count]", text: "1", exact: true)
    end

    test "dismisses one device, or all of them", %{
      conn: conn,
      org: org,
      product: product,
      notifications: [first | _]
    } do
      conn
      |> visit(page_path(org, product))
      |> click_button("#notification-wrong_websocket_host button[aria-label='Show the 3 devices']", "")
      |> click_button("#notification-#{first.id} button", "Dismiss")
      |> assert_has("#notification-wrong_websocket_host h3", text: "2 devices connected to the wrong host.")
      |> assert_has("#notification-wrong_websocket_host-devices li", count: 2)
      |> click_button("Dismiss all 2")
      |> assert_has("[role=alert]", text: "Dismissed “2 devices connected to the wrong host.”")
      |> assert_has("#notifications-empty")

      assert Repo.aggregate(Notification, :count) == 0
    end

    test "lists the most recent devices until asked for all of them", %{conn: conn, org: org, product: product} do
      for n <- 1..10, do: wrong_host!(product, "more-#{n}")

      conn
      |> visit(page_path(org, product))
      |> click_button("#notification-wrong_websocket_host button[aria-label='Show the 13 devices']", "")
      |> assert_has("#notification-wrong_websocket_host-devices li", count: 10)
      |> click_button("Show all 13 devices")
      |> assert_has("#notification-wrong_websocket_host-devices li", count: 13)
      |> refute_has("button", text: "Show all 13 devices")
    end

    test "lists one device's notifications when it has more than one", %{conn: conn, org: org, product: product} do
      device_info = %DeviceInfo{product_id: product.id, device_identifier: "abc"}
      _ = ProductNotifications.create_extension_failure_notification!(device_info, "geo", ":enoent")
      _ = ProductNotifications.create_extension_failure_notification!(device_info, "local_shell", ":no_pty")

      conn
      |> visit(page_path(org, product))
      |> assert_has("#notification-extension_failure h3", text: "A device had 2 extension failures.")
      |> assert_has("#notification-extension_failure", text: "1 device")
      |> click_button("#notification-extension_failure button[aria-label='Show the 2 notifications']", "")
      |> assert_has("#notification-extension_failure-devices li", text: "geo: :enoent")
      |> assert_has("#notification-extension_failure-devices li", text: "local_shell: :no_pty")
      |> assert_has("button", text: "Dismiss all 2")
    end

    test "counts up when another device joins it", %{conn: conn, org: org, product: product} do
      conn
      |> visit(page_path(org, product))
      |> assert_has("#notification-wrong_websocket_host", text: "3 devices")
      |> tap(fn _ -> wrong_host!(product, "a-fourth") end)
      |> assert_has("#notification-wrong_websocket_host h3", text: "4 devices connected to the wrong host.")
      |> refute_has("#notification-wrong_websocket_host", text: "New")
    end

    test "can't be dismissed by a member with the view role", %{conn: conn, org: org, product: product} do
      Repo.update_all(OrgUser, set: [role: :view])

      conn =
        conn
        |> visit(page_path(org, product))
        |> click_button("#notification-wrong_websocket_host button[aria-label='Show the 3 devices']", "")
        |> assert_has("#notification-wrong_websocket_host-devices li", count: 3)
        |> refute_has("#notification-wrong_websocket_host-devices button", text: "Dismiss")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "dismiss-card", %{"key" => "wrong_websocket_host"}))

      assert Repo.aggregate(Notification, :count) == 3
    end
  end

  describe "arriving while the page is open" do
    test "on the first page, a new one is tagged New", %{conn: conn, org: org, product: product} do
      _ = many!(product, 2)

      conn
      |> visit(page_path(org, product))
      |> tap(fn _ -> code_failure!(product, "snootboop") end)
      |> assert_has("article", text: "snootboop")
      |> assert_has("article", text: "New")
      |> assert_has("#level-all", text: "3")
    end

    test "on the first page, one that happens again counts up without a New tag", %{
      conn: conn,
      org: org,
      product: product
    } do
      notification = product |> code_failure!("abc") |> last_occurred!(600)

      conn
      |> visit(page_path(org, product))
      |> tap(fn _ -> code_failure!(product, "abc") end)
      |> assert_has("#notification-#{notification.id}", text: "2 times")
      |> refute_has("#notification-#{notification.id}", text: "New")
    end

    test "on a later page, a bar says it's on the first page and the list stays put", %{
      conn: conn,
      org: org,
      product: product
    } do
      _ = many!(product, 30)

      conn
      |> visit(page_path(org, product, "?page_number=2"))
      |> assert_has("article", text: "abc-30")
      |> tap(fn _ -> code_failure!(product, "snootboop") end)
      |> assert_has("#arrived-elsewhere", text: "1 new notification on the first page")
      |> refute_has("article", text: "snootboop")
      |> click_link("Go to newest")
      |> assert_has("article", text: "snootboop")
    end
  end

  describe "pages" do
    test "a page that starts partway through a day says it continues", %{conn: conn, org: org, product: product} do
      _ = many!(product, 30)

      conn
      |> visit(page_path(org, product))
      |> assert_has("#notifications-pager", text: "1–25 of 30")
      |> refute_has("article", text: "abc-26")
      |> unwrap(fn view -> view |> element("button[aria-label='Next page']") |> render_click() end)
      |> assert_has("#notifications-pager", text: "26–30 of 30")
      |> assert_has("#day-today h2", text: "continued")
      |> assert_has("article", text: "abc-26")
    end

    test "can show more per page", %{conn: conn, org: org, product: product} do
      _ = many!(product, 30)

      conn
      |> visit(page_path(org, product))
      |> unwrap(fn view -> view |> element("#notifications-page-size") |> render_change(%{"page-size" => "50"}) end)
      |> assert_has("article", text: "abc-30")
      |> assert_has("#notifications-pager", text: "1–30 of 30")
    end

    test "a page past the end shows the last page", %{conn: conn, org: org, product: product} do
      _ = many!(product, 3)

      conn
      |> visit(page_path(org, product, "?page_number=4&page_size=nonsense&level=nonsense"))
      |> assert_has("article", count: 3)
    end
  end
end
