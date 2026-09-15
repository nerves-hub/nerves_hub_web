defmodule NervesHubWeb.Live.Product.InsightsPenaltyBoxTest do
  # Not async: the Insights page reads the AnalyticsRepo (ClickHouse) for its
  # other panels, like its siblings here. The penalty box panel itself is
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

  defp block_updates(device, opts) do
    blocked_for = Keyword.get(opts, :blocked_for, 60)

    {:ok, device} =
      Devices.update_device(device, %{
        updates_blocked_until: DateTime.add(DateTime.utc_now(:second), blocked_for, :minute),
        consecutive_failed_updates: Keyword.fetch!(opts, :failures)
      })

    device
  end

  describe "the penalty box panel" do
    test "lists blocked devices worst first, with their consecutive failure counts", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _unlucky_once = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 1)
      stuck = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 27)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Penalty Box"
      assert html =~ "27 failed"
      assert html =~ "1 failed"

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.penalty_box_count == 2
      assert [%{id: first_id}, _] = assigns.penalty_box_devices
      assert first_id == stuck.id
    end

    test "leaves out devices whose block has already lifted, and those never blocked", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _never_blocked = Fixtures.device_fixture(org, product, firmware)
      _served_its_time = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 4, blocked_for: -60)

      blocked = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 2)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assigns = :sys.get_state(view.pid).socket.assigns

      assert assigns.penalty_box_count == 1
      assert [%{id: only_id}] = assigns.penalty_box_devices
      assert only_id == blocked.id
    end

    test "says so rather than showing a zero when nothing has been counted yet", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      # A device already blocked when the platform started counting has no run
      # of failures behind it to show.
      _blocked = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 0)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "none recorded"
      refute html =~ "0 failed"
    end

    test "shows an empty state when no device is blocked", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _device = Fixtures.device_fixture(org, product, firmware)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "No devices in the penalty box"

      assert :sys.get_state(view.pid).socket.assigns.penalty_box_count == 0
    end

    test "links to the penalty box filter on the devices list", %{
      conn: conn,
      org: org,
      product: product,
      firmware: firmware
    } do
      _blocked = block_updates(Fixtures.device_fixture(org, product, firmware), failures: 3)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ "devices?updates=penalty-box"
    end
  end
end
