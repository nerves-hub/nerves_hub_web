defmodule NervesHubWeb.Live.Product.InsightsUpdateHistoryTest do
  # Not async: these tests read/write the AnalyticsRepo (ClickHouse) and toggle
  # the global :analytics_enabled application env.
  use NervesHubWeb.ConnCase.Browser, async: false
  use AssertEventually, timeout: 2000, interval: 50

  import Phoenix.LiveViewTest

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceUpdateHistory
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Rollout Health"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_update_history")

    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_update_history") end)

    %{product: product, firmware: firmware, device: device}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  # Midday keeps the row on the day intended whichever timezone the query
  # buckets in, rather than landing it on a neighbour by a couple of hours.
  defp record(device, status, days_ago) do
    timestamp = DateTime.new!(Date.add(Date.utc_today(), -days_ago), ~T[12:00:00], "Etc/UTC")

    :ok = UpdateHistory.record(device, status, timestamp: timestamp)
  end

  defp recorded(device, count) do
    :ok = Buffer.flush(DeviceUpdateHistory)

    assert_eventually(
      length(Enum.filter(AnalyticsRepo.all(DeviceUpdateHistory), &(&1.device_id == device.id))) == count
    )
  end

  describe "when analytics is enabled" do
    test "renders the graph with the per-day outcome data", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      record(device, :succeeded, 1)
      record(device, :failed, 1)
      record(device, :abandoned, 1)
      record(device, :succeeded, 0)
      recorded(device, 4)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Firmware Update History"
      assert html =~ "update-outcomes-chart"
      assert html =~ ~s(phx-hook="UpdateOutcomesChart")

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_graph_enabled
      assert assigns.update_outcomes_graph_from == Date.add(Date.utc_today(), -14)
      assert assigns.update_outcomes_graph_to == Date.utc_today()

      by_day = Map.new(assigns.update_outcomes_graph_data, &{&1.day, &1})

      assert by_day[Date.add(Date.utc_today(), -1)].succeeded == 1
      assert by_day[Date.add(Date.utc_today(), -1)].failed == 2
      assert by_day[Date.utc_today()].succeeded == 1
      assert by_day[Date.utc_today()].failed == 0
    end

    test "totals the window in the legend, alongside the share that failed", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      for _ <- 1..3, do: record(device, :succeeded, 2)
      record(device, :failed, 2)
      recorded(device, 4)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_succeeded == 3
      assert assigns.update_outcomes_failed == 1

      assert html =~ "Successful"
      assert html =~ "Failed"
      assert html =~ "25% of attempts failed"
    end

    test "leaves a reschedule out of both series, because deferring is not failing", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      record(device, :rescheduled, 1)
      recorded(device, 1)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_succeeded == 0
      assert assigns.update_outcomes_failed == 0
    end

    test "still renders the graph (zero-filled) when there is no history", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Firmware Update History"

      data = :sys.get_state(view.pid).socket.assigns.update_outcomes_graph_data

      refute data == []
      assert Enum.all?(data, &(&1.succeeded == 0 and &1.failed == 0))
    end

    test "does not load the graph on the disconnected (dead) mount", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      record(device, :failed, 0)
      recorded(device, 1)

      html = conn |> get(insights_path(org, product)) |> html_response(200)
      refute html =~ "update-outcomes-chart"

      {:ok, _view, connected_html} = live(conn, insights_path(org, product))
      assert connected_html =~ "update-outcomes-chart"
    end

    test "defaults to the 14 day period", %{conn: conn, org: org, product: product} do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_period == :fourteen_days
      assert assigns.update_outcomes_graph_unit == "day"
    end

    test "selecting the 4 week period extends the window to 28 days", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      view
      |> element(~s(#update-outcomes-period button[phx-value-period="four_weeks"]))
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_period == :four_weeks
      assert assigns.update_outcomes_graph_unit == "day"
      assert assigns.update_outcomes_graph_from == Date.add(Date.utc_today(), -28)
      assert assigns.update_outcomes_graph_to == Date.utc_today()
    end

    test "selecting the 24 hour period switches to hourly granularity", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      view
      |> element(~s(#update-outcomes-period button[phx-value-period="twenty_four_hours"]))
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_period == :twenty_four_hours
      assert assigns.update_outcomes_graph_unit == "hour"
      assert %DateTime{} = assigns.update_outcomes_graph_from
      assert %DateTime{} = assigns.update_outcomes_graph_to
    end

    test "leaves the connections graph's own period alone", %{conn: conn, org: org, product: product} do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      view
      |> element(~s(#update-outcomes-period button[phx-value-period="four_weeks"]))
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.update_outcomes_period == :four_weeks
      assert assigns.connected_devices_period == :fourteen_days
    end
  end

  describe "when analytics is disabled" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)

      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)

      :ok
    end

    test "the graph is not rendered at all", %{conn: conn, org: org, product: product} do
      {:ok, view, html} = live(conn, insights_path(org, product))

      refute html =~ "Firmware Update History"
      refute html =~ "update-outcomes-chart"

      refute :sys.get_state(view.pid).socket.assigns.update_outcomes_graph_enabled
    end

    test "the penalty box panel is still there, because it does not need analytics", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "Penalty Box"
    end
  end
end
