defmodule NervesHubWeb.Live.Product.InsightsTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.Accounts
  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceHealthHistory
  alias NervesHub.Devices.Health
  alias NervesHub.Fixtures
  alias NervesHub.ProductNotifications
  alias NervesHub.Products

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Fleet Insights"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{product: product, firmware: firmware}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  # Each device has at most one connection row (unique on device_id), which the
  # latest_connection has_one association resolves to.
  defp connect_device(device, params) do
    Fixtures.device_connection_fixture(device, params)
  end

  defp set_health(device, status) do
    {:ok, _} =
      Health.save_device_health(%{
        "device_id" => device.id,
        "data" => %{},
        "status" => status,
        "status_reasons" => %{}
      })
  end

  describe "rendering" do
    test "renders the dashboard with the fleet size and section headings", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      device = Fixtures.device_fixture(org, product, firmware)
      set_health(device, :healthy)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "Insights"
      assert html =~ "1 device"
      assert html =~ "What the fleet is made of"
      assert html =~ "Health and connection by firmware version"
      assert html =~ "Notifications"
    end
  end

  describe "empty states" do
    test "shows an onboarding message for a product with no devices", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Insights"
      assert html =~ "0 devices"
      assert html =~ "#{product.name} doesn"
      assert html =~ "have any devices yet"
      # the composition is hidden when there are no devices
      refute html =~ "What the fleet is made of"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.fleet_size == 0
      refute assigns.stands_out
    end

    test "the onboarding message includes the shared secret for manage members", %{
      conn: conn,
      org: org,
      user: user,
      product: product
    } do
      {:ok, shared_secret} = Products.create_shared_secret_auth(product)
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :manage)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ shared_secret.secret
    end

    test "the onboarding message leaves out the shared secret for view-only members", %{
      conn: conn,
      org: org,
      user: user,
      product: product
    } do
      {:ok, shared_secret} = Products.create_shared_secret_auth(product)
      {:ok, _} = Accounts.change_org_user_role(Accounts.get_org_user!(org, user.id), :view)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "have any devices yet"
      refute html =~ shared_secret.secret
    end

    test "renders when devices exist but have no health records", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "What the fleet is made of"
      assert :sys.get_state(view.pid).socket.assigns.composition.health.unknown == 1
    end
  end

  describe "polling" do
    test "recounts the fleet on each poll", %{conn: conn, org: org, product: product, firmware: firmware} do
      device = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, _html} = live(conn, insights_path(org, product))
      assert :sys.get_state(view.pid).socket.assigns.composition.connection.online == 0

      connect_device(device, %{status: :connected})
      send(view.pid, :poll_device_counts)

      # render/1 waits for the poll to be handled
      render(view)
      assert :sys.get_state(view.pid).socket.assigns.composition.connection.online == 1
    end
  end

  describe "notifications" do
    test "lists product notifications with a count", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      # the dashboard (incl. the notifications panel) only renders with devices
      Fixtures.device_fixture(org, product, firmware)

      ProductNotifications.create_duplicate_device_identifier_notification!(
        product.id,
        "abc",
        :shared_secrets
      )

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "already exists"
      assert :sys.get_state(view.pid).socket.assigns.notification_count == 1
    end

    test "shows an empty state when there are no notifications", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "No notifications"
      assert :sys.get_state(view.pid).socket.assigns.notification_count == 0
    end

    test "only shows notifications for the product being viewed", %{
      conn: conn,
      org: org,
      user: user,
      product: product
    } do
      other_product = Fixtures.product_fixture(user, org, %{name: "Other Product"})

      ProductNotifications.create_duplicate_device_identifier_notification!(
        other_product.id,
        "abc",
        :shared_secrets
      )

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assert :sys.get_state(view.pid).socket.assigns.notification_count == 0
    end
  end

  describe "auto refresh" do
    test "is enabled on mount and can be toggled off and on", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      # auto refresh polling is started on mount
      assert :sys.get_state(view.pid).socket.assigns.polling_pid
      assert has_element?(view, "button[phx-click=toggle-auto-refresh][aria-checked=true]")

      render_click(view, "toggle-auto-refresh")

      refute :sys.get_state(view.pid).socket.assigns.polling_pid
      assert has_element?(view, "button[phx-click=toggle-auto-refresh][aria-checked=false]")

      render_click(view, "toggle-auto-refresh")

      assert :sys.get_state(view.pid).socket.assigns.polling_pid
    end
  end

  describe "flapping health" do
    setup %{org: org, product: product, firmware: firmware} do
      AnalyticsRepo.query!("TRUNCATE TABLE device_health_history")
      on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_health_history") end)

      %{device: Fixtures.device_fixture(org, product, firmware)}
    end

    defp record_health(device, status, count) do
      for _ <- 1..count do
        Buffer.insert(
          DeviceHealthHistory,
          DeviceHealthHistory.changeset(%{
            timestamp: DateTime.utc_now(),
            org_id: device.org_id,
            product_id: device.product_id,
            device_id: device.id,
            status: status,
            status_reasons: ""
          })
        )
      end

      :ok = Buffer.flush(DeviceHealthHistory)
    end

    test "lists a device that keeps changing its mind", %{conn: conn, org: org, product: product, device: device} do
      record_health(device, "warning", 6)

      conn
      |> visit(insights_path(org, product))
      |> within("#flapping", fn session ->
        session
        |> assert_has("a", text: device.identifier)
        |> assert_has("span", text: "health")
        |> assert_has("span", text: "6/h")
      end)
    end

    test "says so when nothing is flapping", %{conn: conn, org: org, product: product, device: device} do
      record_health(device, "warning", 2)

      conn
      |> visit(insights_path(org, product))
      |> assert_has("#flapping", text: "Nothing has flapped in the last hour")
      |> refute_has("#flapping", text: device.identifier)
    end
  end
end
