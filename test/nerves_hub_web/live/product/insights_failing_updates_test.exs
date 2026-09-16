defmodule NervesHubWeb.Live.Product.InsightsFailingUpdatesTest do
  # Not async: the Insights page reads the AnalyticsRepo (ClickHouse) for its
  # other panels, like its siblings here. The failing updates panel itself is
  # PostgreSQL only.
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.Devices
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Blocked Updates"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})

    %{product: product, firmware: firmware}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  # A device as the panel needs it: blocked, with a run of failures behind it.
  defp failing(device, opts) do
    blocked_for = Keyword.get(opts, :blocked_for, 60)
    failures = Keyword.fetch!(opts, :failures)
    failing_since = Keyword.get(opts, :failing_since)

    {:ok, device} =
      Devices.update_device(device, %{
        updates_blocked_until: DateTime.add(DateTime.utc_now(:second), blocked_for, :minute),
        consecutive_failed_updates: failures,
        first_update_failure_at: failing_since
      })

    device
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(:second), -days, :day)

  describe "the failing updates panel" do
    test "lists failing devices worst first, with their consecutive failure counts", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _unlucky_once = failing(Fixtures.device_fixture(org, product, firmware), failures: 1)
      stuck = failing(Fixtures.device_fixture(org, product, firmware), failures: 27)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Failed Firmware Updates"
      assert html =~ "27 failed"
      assert html =~ "1 failed"

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.failing_count == 2
      assert [%{id: first_id}, _] = assigns.failing_devices
      assert first_id == stuck.id
    end

    test "says how long each device has been failing", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _ = failing(Fixtures.device_fixture(org, product, firmware), failures: 40, failing_since: days_ago(14))

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "over 14 days"
    end

    test "leaves out a device that is blocked but has not failed", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      # A device that asked to be rescheduled is blocked and has failed at
      # nothing, so it does not belong under a heading about failures.
      _rescheduled = failing(Fixtures.device_fixture(org, product, firmware), failures: 0)
      failing_device = failing(Fixtures.device_fixture(org, product, firmware), failures: 3)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.failing_count == 1
      assert [%{id: only_id}] = assigns.failing_devices
      assert only_id == failing_device.id
    end

    test "leaves out devices whose block has already lifted, and those never blocked", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _never_blocked = Fixtures.device_fixture(org, product, firmware)
      _served_its_time = failing(Fixtures.device_fixture(org, product, firmware), failures: 4, blocked_for: -60)

      blocked = failing(Fixtures.device_fixture(org, product, firmware), failures: 2)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.failing_count == 1
      assert [%{id: only_id}] = assigns.failing_devices
      assert only_id == blocked.id
    end

    test "shows an empty state when nothing is failing", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _device = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "No devices are failing to update"

      assert :sys.get_state(view.pid).socket.assigns.failing_count == 0
    end

    test "links to the penalty box filter on the devices list", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _blocked = failing(Fixtures.device_fixture(org, product, firmware), failures: 3)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "devices?updates=penalty-box"
    end
  end
end
