defmodule NervesHubWeb.Live.Product.InsightsFlappingConnectionsTest do
  # Not async: these tests read/write the AnalyticsRepo (ClickHouse) and toggle
  # the global :analytics_enabled application env.
  use NervesHubWeb.ConnCase.Browser, async: false

  import Phoenix.LiveViewTest

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Fixtures

  setup %{user: user, org: org, org_key: org_key, tmp_dir: tmp_dir} do
    product = Fixtures.product_fixture(user, org, %{name: "Conn Stability"})
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")

    on_exit(fn ->
      AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")
    end)

    %{product: product, firmware: firmware, device: device}
  end

  defp insights_path(org, product), do: ~p"/org/#{org}/#{product}/insights"

  # Inserts `count` recent connection-history rows for `device`, each with a
  # distinct `established_at` so the ReplacingMergeTree (keyed on
  # org/product/device/established_at) does not collapse them when queried FINAL.
  defp insert_connections(device, count) do
    base = DateTime.add(DateTime.utc_now(), -5, :minute)

    for offset <- 1..count do
      established_at = DateTime.add(base, -offset, :second)

      connection = %DeviceConnection{
        id: Ecto.UUID.generate(version: 7),
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: established_at,
        last_seen_at: DateTime.utc_now(),
        disconnected_at: DateTime.utc_now()
      }

      {:ok, _} =
        connection
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()
    end

    :ok
  end

  describe "when analytics is enabled" do
    test "lists flapping devices with their hourly reconnection count", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      insert_connections(device, 11)

      {:ok, view, html} = live(conn, insights_path(org, product))

      assert html =~ "Flapping"
      assert has_element?(view, "#flapping", device.identifier)
      assert has_element?(view, "#flapping", "connection")
      assert has_element?(view, "#flapping", "11/h")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.flapping_enabled
      assert [%{device: flapping_device, kind: "connection", count: 11}] = assigns.flapping
      assert flapping_device.id == device.id
    end

    test "links each flapping device to its device page", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      insert_connections(device, 11)

      {:ok, _view, html} = live(conn, insights_path(org, product))

      assert html =~ ~p"/org/#{org}/#{product}/devices/#{device.identifier}"
    end

    test "shows an empty state when no devices are flapping", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      # below the threshold, so this device should not be reported
      insert_connections(device, 5)

      {:ok, view, _html} = live(conn, insights_path(org, product))

      assert has_element?(view, "#flapping", "Nothing has flapped in the last hour")
      refute has_element?(view, "#flapping", device.identifier)

      assert :sys.get_state(view.pid).socket.assigns.flapping == []
    end
  end

  describe "when analytics is disabled" do
    setup do
      original = Application.get_env(:nerves_hub, :analytics_enabled)
      Application.put_env(:nerves_hub, :analytics_enabled, false)
      on_exit(fn -> Application.put_env(:nerves_hub, :analytics_enabled, original) end)
      :ok
    end

    test "does not render the flapping list", %{
      conn: conn,
      org: org,
      product: product
    } do
      {:ok, view, _html} = live(conn, insights_path(org, product))

      refute has_element?(view, "#flapping")
      refute :sys.get_state(view.pid).socket.assigns.flapping_enabled
    end
  end
end
