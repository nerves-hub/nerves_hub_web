defmodule NervesHubWeb.Live.Product.InsightsConnectionsGraphTest do
  # Not async: these tests read/write the AnalyticsRepo (ClickHouse) and toggle
  # the global :analytics_enabled application env.
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Connections Graph"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")

    %{product: product, firmware: firmware, device: device}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  defp insert_history(device, established_at, disconnected_at) do
    connection = %DeviceConnection{
      id: UUIDv7.generate(),
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      established_at: established_at,
      last_seen_at: disconnected_at || DateTime.utc_now(),
      disconnected_at: disconnected_at
    }

    {:ok, _} =
      connection
      |> DeviceConnectionHistory.from_device_connection_changeset()
      |> AnalyticsRepo.insert()
  end

  describe "when analytics is enabled" do
    test "renders the connections graph with the per-day connection data", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # device connected 2 days ago and is still connected
      insert_history(device, DateTime.add(DateTime.utc_now(), -2, :day), nil)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Connected Device History"
      assert html =~ "daily-device-counts-chart"
      assert html =~ ~s(phx-hook="BarChart")

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.device_connections_graph_enabled
      assert assigns.device_connections_graph_from == Date.add(Date.utc_today(), -14)
      assert assigns.device_connections_graph_to == Date.utc_today()

      counts =
        Map.new(assigns.device_connections_graph_data, fn %{day: day, count: count} ->
          {day, count}
        end)

      assert counts[Date.utc_today()] == 1
      assert counts[Date.add(Date.utc_today(), -1)] == 1
    end

    test "encodes the graph data into the chart's data-metrics attribute", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      insert_history(device, DateTime.add(DateTime.utc_now(), -1, :day), nil)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      [_, encoded] = Regex.run(~r/data-metrics="([^"]*)"/, html)

      # the chart receives a (HTML-escaped) JSON array of day/unique_devices entries
      assert encoded =~ "count"
      assert encoded =~ "day"
    end

    test "still renders the graph (with empty data) when there is no history", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Connected Device History"
      assert :sys.get_state(view.pid).socket.assigns.device_connections_graph_data == []
    end

    test "defaults to the 14 day period", %{conn: conn, org: org, product: product} do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.connected_devices_period == :fourteen_days
      assert assigns.device_connections_graph_unit == "day"
      assert assigns.device_connections_graph_from == Date.add(Date.utc_today(), -14)
      assert assigns.device_connections_graph_to == Date.utc_today()
    end

    test "renders a tab for each available period", %{conn: conn, org: org, product: product} do
      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ ~s(phx-value-period="twenty_four_hours")
      assert html =~ ~s(phx-value-period="fourteen_days")
      assert html =~ ~s(phx-value-period="four_weeks")
    end

    test "selecting the 4 week period extends the window to 28 days", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      view
      |> element(~s(button[phx-value-period="four_weeks"]))
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.connected_devices_period == :four_weeks
      assert assigns.device_connections_graph_unit == "day"
      assert assigns.device_connections_graph_from == Date.add(Date.utc_today(), -28)
      assert assigns.device_connections_graph_to == Date.utc_today()
    end

    test "selecting the 24 hour period switches to hourly granularity", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      insert_history(device, DateTime.add(DateTime.utc_now(), -2, :hour), nil)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      view
      |> element(~s(button[phx-value-period="twenty_four_hours"]))
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.connected_devices_period == :twenty_four_hours
      assert assigns.device_connections_graph_unit == "hour"
      assert %DateTime{} = assigns.device_connections_graph_from
      assert %DateTime{} = assigns.device_connections_graph_to

      # the window spans roughly the last 24 hours
      diff = DateTime.diff(assigns.device_connections_graph_to, assigns.device_connections_graph_from, :hour)
      assert diff == 24

      # the device connected 2 hours ago shows up in the hourly data
      assert Enum.sum(Enum.map(assigns.device_connections_graph_data, & &1.count)) >= 1
    end

    test "marks the active period tab as selected", %{conn: conn, org: org, product: product} do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      html =
        view
        |> element(~s(button[phx-value-period="four_weeks"]))
        |> render_click()

      # the chart's id is keyed on the active period, forcing the hook to remount
      assert html =~ "daily-device-counts-chart-four_weeks"
    end

    test "an unknown period is rejected with a flash message", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      html = render_click(view, "select-graph-time-period", %{"period" => "all_time"})

      assert html =~ "Invalid graph period selected"
      # the period is unchanged
      assert :sys.get_state(view.pid).socket.assigns.connected_devices_period == :fourteen_days
    end
  end

  describe "when analytics is disabled" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
      :ok
    end

    test "does not render the connections graph", %{conn: conn, org: org, product: product} do
      {:ok, view, html} = live(conn, insights_path(org, product))

      refute html =~ "Connected Device History"
      refute html =~ "daily-device-counts-chart"

      refute :sys.get_state(view.pid).socket.assigns.device_connections_graph_enabled
    end
  end
end
