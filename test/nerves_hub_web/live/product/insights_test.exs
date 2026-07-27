defmodule NervesHubWeb.Live.Product.InsightsTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  import Phoenix.LiveViewTest

  alias NervesHub.Devices
  alias NervesHub.Fixtures
  alias NervesHub.ProductNotifications

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
      Devices.save_device_health(%{
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
      # seed a health record so the fleet health breakdown has data to show
      set_health(device, :healthy)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "Insights"
      assert html =~ "1 device"
      assert html =~ "Online now"
      assert html =~ "Offline"
      assert html =~ "Not seen in 7 days"
      assert html =~ "Not seen in 14 days"
      assert html =~ "Fleet Health"
      assert html =~ "Healthy"
      assert html =~ "Warning"
      assert html =~ "Unhealthy"
      assert html =~ "Unknown"
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
      # the dashboard cards are hidden when there are no devices
      refute html =~ "% of fleet"

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.fleet_size == 0
      assert assigns.online_count == 0
    end

    test "renders when devices exist but have no health records", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Fleet Health"
      assert html =~ "Healthy"

      assert :sys.get_state(view.pid).socket.assigns.total_health_count == 0
    end
  end

  describe "device connection counts" do
    test "counts online, offline, and not-seen devices", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      now = DateTime.utc_now()

      online = Fixtures.device_fixture(org, product, firmware)
      connect_device(online, %{status: :connected})

      offline_recent = Fixtures.device_fixture(org, product, firmware)
      connect_device(offline_recent, %{status: :disconnected, disconnected_at: now})

      offline_8_days = Fixtures.device_fixture(org, product, firmware)
      connect_device(offline_8_days, %{status: :disconnected, disconnected_at: DateTime.add(now, -8, :day)})

      offline_15_days = Fixtures.device_fixture(org, product, firmware)
      connect_device(offline_15_days, %{status: :disconnected, disconnected_at: DateTime.add(now, -15, :day)})

      # a device that has never connected counts as offline and not seen
      _never_connected = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.fleet_size == 5
      assert assigns.online_count == 1
      assert assigns.offline_count == 4
      # offline_8_days, offline_15_days, never_connected
      assert assigns.not_seen_in_7_days == 3
      # offline_15_days, never_connected
      assert assigns.not_seen_in_14_days == 2
    end
  end

  describe "fleet health" do
    test "counts devices by health status", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      for status <- [:healthy, :healthy, :warning, :unhealthy, :unknown] do
        org
        |> Fixtures.device_fixture(product, firmware)
        |> set_health(status)
      end

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.healthy_count == 2
      assert assigns.warning_count == 1
      assert assigns.unhealthy_count == 1
      assert assigns.unknown_count == 1
      assert assigns.total_health_count == 5
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

      assert html =~ "You have no notifications"
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
      assert render(view) =~ "bg-primary"

      render_click(view, "toggle-auto-refresh")

      refute :sys.get_state(view.pid).socket.assigns.polling_pid
      assert render(view) =~ "bg-gray-200"

      render_click(view, "toggle-auto-refresh")

      assert :sys.get_state(view.pid).socket.assigns.polling_pid
    end
  end
end
