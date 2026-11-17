defmodule NervesHubWeb.Live.Devices.IndexTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Ecto.Query, only: [from: 2, where: 2]

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHub.DeviceEvents
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.InflightUpdate
  alias NervesHub.Devices.Metrics
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Fixtures
  alias NervesHub.Repo
  alias NervesHubWeb.Components.ListSettingsSidebar
  alias NervesHubWeb.Endpoint
  alias Phoenix.Socket.Broadcast

  setup %{fixture: %{device: device}} do
    Endpoint.subscribe("device:#{device.id}")
  end

  test "user is redirected to login when trying to access a products device list, but the user isn't logged in" do
    build_conn()
    |> visit("/org/snoot/boop/devices")
    |> assert_path("/login")
    |> assert_has("div", text: "You must login to access this page.")
  end

  test "shows a loading message (async loading)", %{conn: conn, fixture: fixture} do
    %{device: device, org: org, product: product} = fixture

    {:ok, lv, html} = live(conn, ~p"/org/#{org}/#{product}/devices")

    assert html =~ "Loading..."

    assert render_async(lv) =~ device.identifier
  end

  describe "refreshing device list" do
    test "refreshes when page is visible", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("span", text: device.firmware_metadata.version, timeout: 1000)
      |> unwrap(fn view ->
        # TODO: (nshoes)
        # The original intent of this test was to update the firmware version and allow the
        # liveview to refresh and assert on the new version. However, PhoenixTest doesn't seem
        # to trigger the `Phoenix.LiveView.handle_async/3` callback, making testing
        # the refreshed results impossible.
        #
        # As it stands, this test just makes sure there's no regression in the `refresh_device_list`
        # message handling.

        # {:ok, device} =
        #   Devices.update_device(device, %{
        #     firmware_metadata: %{Map.from_struct(device.firmware_metadata) | version: "2.0.0"}
        #   })

        send(view.pid, :refresh_device_list)

        render_async(view)
      end)
    end
  end

  describe "device connection status updates" do
    setup context do
      Map.merge(context, %{
        offline_indicator: "span.bg-status-offline",
        online_indicator: "span.bg-status-online"
      })
    end

    test "connection:change", %{
      conn: conn,
      fixture: fixture,
      offline_indicator: offline_indicator,
      online_indicator: online_indicator
    } do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has(offline_indicator, timeout: 1000)
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{status: "online"}
        })

        render_async(view)
      end)
      |> assert_has(online_indicator)
    end
  end

  describe "device firmware updates" do
    test "shows information when the update is requested", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "requested")
    end

    test "shows information when the update is received by the device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "received", nil, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "received")
    end

    test "shows information when the update is being downloaded by the device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "downloading", 50, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "downloading")
    end

    test "shows information when the update is being applied by the device", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "updating", 50, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "updating")
    end

    test "shows information when the update 'expires'", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "expired", nil, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "expired")
    end

    test "shows information when the update completes successfully", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "completed", nil, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("span", text: "completed")
    end

    test "responds to pubsub updates", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "requested", nil, false)
        render(view)
      end)
      |> assert_has("div", text: "requested")
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "received", nil, false)
        render(view)
      end)
      |> assert_has("div", text: "received")
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "started", nil, false)
        render(view)
      end)
      |> assert_has("div", text: "started")
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "downloading", 35, false)
        render(view)
      end)
      |> assert_has("div", text: "downloading")
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "updating", 70, false)
        render(view)
      end)
      |> assert_has("div", text: "updating")
      |> unwrap(fn view ->
        FirmwareUpdates.update_inflight_update(device.id, "completed", nil, false)
        render(view)
      end)
      |> assert_has("div", text: "completed")
    end

    test "hides banner after the device has restarted", %{
      conn: conn,
      org: org,
      product: product,
      device: device,
      firmware: firmware
    } do
      {:ok, _inflight_update} =
        InflightUpdate.manual_requested_changeset(device.id, firmware)
        |> Repo.insert()

      FirmwareUpdates.update_inflight_update(device.id, "completed", nil, true)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> assert_has("div", text: "completed")
      |> unwrap(fn view ->
        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{status: "offline"}
        })

        render(view)
      end)
      |> assert_has("div", text: "completed")
      |> unwrap(fn view ->
        Repo.delete_all(InflightUpdate)

        send(view.pid, %Broadcast{
          topic: "internal:device:#{device.id}",
          event: "connection:change",
          payload: %{status: "online"}
        })

        render_async(view)
      end)
      |> refute_has("div", text: "completed")
    end
  end

  describe "filtering devices" do
    test "by exact identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> visit(device_index_path(fixture) <> "?" <> URI.encode_query(identifier: device.identifier))
      |> assert_has("#filter-token-identifier", timeout: 1000)
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by wrong identifier", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> visit(device_index_path(fixture) <> "?" <> URI.encode_query(identifier: "foo"))
      |> assert_has("#filter-token-identifier", timeout: 1000)
      |> assert_has("#device-count", text: "0", timeout: 1000)
    end

    test "by prefix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> visit(device_index_path(fixture) <> "?" <> URI.encode_query(identifier: "device-"))
      |> assert_has("#filter-token-identifier", timeout: 1000)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by suffix identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      "device-" <> just_the_tail = device.identifier

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> visit(device_index_path(fixture) <> "?" <> URI.encode_query(identifier: just_the_tail))
      |> assert_has("#filter-token-identifier", timeout: 1000)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by middle identifier", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> visit(device_index_path(fixture) <> "?" <> URI.encode_query(identifier: "ice-"))
      |> assert_has("#filter-token-identifier", timeout: 1000)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by platform", %{conn: conn, fixture: fixture, tmp_dir: tmp_dir} do
      %{
        device: device,
        org: org,
        product: product,
        user: user
      } = fixture

      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      foo_firmware = Fixtures.firmware_fixture(org_key, product, %{platform: "foo", dir: tmp_dir})
      device2 = Fixtures.device_fixture(org, product, foo_firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> open_filters()
      |> select("Platform", option: "foo")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
      |> select("Platform", option: "platform")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
    end

    test "the firmware filter only lists versions devices are running", %{
      conn: conn,
      fixture: fixture,
      tmp_dir: tmp_dir
    } do
      %{device: device, org: org, product: product, user: user} = fixture

      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

      # uploaded to the product, but no device is running it
      _unused = Fixtures.firmware_fixture(org_key, product, %{version: "9.9.9", dir: tmp_dir})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> open_filters()
      |> assert_has("#filter-firmware_version label", text: device.firmware_metadata.version, timeout: 1000)
      |> refute_has("#filter-firmware_version label", text: "9.9.9")
    end

    # `Devices.filter/3` preloads only the columns behind the health icon and its
    # tooltip, so this asserts the tooltip still has what it renders from.
    test "renders the health reasons from the trimmed preload", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product, firmware: firmware} = fixture

      healthy = Fixtures.device_fixture(org, product, firmware)

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => healthy.id,
          "data" => %{"metrics" => %{"cpu_temp" => 41.2}},
          "status" => :healthy
        })

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device.id,
          "data" => %{"metrics" => %{"cpu_temp" => 41.2}},
          "status" => :warning,
          "status_reasons" => %{"warning" => %{"cpu_temp" => %{"value" => 41.2, "threshold" => 40}}}
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      # a problem is a chip, with its reasons from `status_reasons` on hover
      |> assert_has("#health-#{device.id}[title*='Cpu Temp: 41.2 (threshold is 40)']", text: "Warning")
      # healthy is plain text
      |> assert_has("#health-#{healthy.id}", text: "Healthy")
    end

    test "by health status", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device2.id,
          "data" => %{},
          "status" => :healthy,
          "status_reasons" => %{}
        })

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> open_filters()
      |> pick("health_status", "unknown", "Unknown")
      # This also asserts that devices with nil health status are listed as unknown
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> unpick("health_status", "unknown", "Unknown")
      |> pick("health_status", "healthy", "Healthy")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
    end

    test "by connected, disconnect, and all", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      assert {:ok, %DeviceConnection{id: ref, status: :connecting}} =
               Connections.device_connecting(device.org_id, device.product_id, device.id)

      Connections.device_connected(ref)

      device2 = Fixtures.device_fixture(org, product, firmware)

      assert {:ok, %DeviceConnection{id: ref2, status: :connecting}} =
               Connections.device_connecting(device2.org_id, device2.product_id, device2.id)

      Connections.device_connected(ref2)
      Connections.device_disconnected(ref2)

      device3 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> assert_has("a", text: device3.identifier)
      |> open_filters()
      |> pick("connection", "connected", "Online")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> refute_has("a", text: device3.identifier)
      |> unpick("connection", "connected", "Online")
      # offline, as the Offline tab counts it, includes a device never connected
      |> pick("connection", "offline", "Offline")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> assert_has("a", text: device3.identifier)
      |> refute_has("a", text: device.identifier)
      |> unpick("connection", "offline", "Offline")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> assert_has("a", text: device.identifier)
      |> assert_has("a", text: device3.identifier)
    end

    test "by connection not seen in 7 days, not seen in 14 days, and not seen at all", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      # first device was last seen 8 days ago

      Device
      |> where(id: ^device.id)
      |> NervesHub.Repo.update_all(set: [status: :provisioned])

      assert {:ok, %DeviceConnection{id: ref, status: :connecting}} =
               Connections.device_connecting(device.org_id, device.product_id, device.id)

      Connections.device_connected(ref)
      Connections.device_disconnected(ref)

      eight_days_ago = DateTime.utc_now() |> DateTime.add(-8, :day)

      DeviceConnection
      |> where(id: ^ref)
      |> NervesHub.Repo.update_all(
        set: [established_at: eight_days_ago, disconnected_at: eight_days_ago, last_seen_at: eight_days_ago]
      )

      # device2 was last seen 16 days ago

      device2 = Fixtures.device_fixture(org, product, firmware, %{status: :provisioned})

      assert {:ok, %DeviceConnection{id: ref2, status: :connecting}} =
               Connections.device_connecting(device2.org_id, device2.product_id, device2.id)

      Connections.device_connected(ref2)
      Connections.device_disconnected(ref2)

      sixteen_days_ago = DateTime.utc_now() |> DateTime.add(-16, :day)

      DeviceConnection
      |> where(id: ^ref2)
      |> NervesHub.Repo.update_all(
        set: [established_at: sixteen_days_ago, disconnected_at: sixteen_days_ago, last_seen_at: sixteen_days_ago]
      )

      # device3 was has never been seen

      device3 = Fixtures.device_fixture(org, product, firmware)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> assert_has("a", text: device3.identifier)
      |> open_filters()
      |> pick("connection", "not_seen_in_seven_days", "Not seen 7 d+")
      |> assert_has("a", text: device.identifier, timeout: 1000)
      |> assert_has("a", text: device2.identifier)
      |> refute_has("a", text: device3.identifier)
      |> unpick("connection", "not_seen_in_seven_days", "Not seen 7 d+")
      |> pick("connection", "not_seen_in_fourteen_days", "Not seen 14 d+")
      |> assert_has("a", text: device2.identifier, timeout: 1000)
      |> refute_has("a", text: device.identifier)
      |> refute_has("a", text: device3.identifier)
      |> unpick("connection", "not_seen_in_fourteen_days", "Not seen 14 d+")
      |> pick("connection", "not_seen", "Never connected")
      |> assert_has("a", text: device3.identifier, timeout: 1000)
      |> refute_has("a", text: device2.identifier)
      |> refute_has("a", text: device.identifier)
    end

    test "by tag", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["filter-test"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> fill_in("#filter-tags", "Tags", with: "filter-test-no-show")
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("#filter-tags", "Tags", with: "filter-test")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "by metrics", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{})

      now = DateTime.utc_now()

      # Explicit timestamps rather than sleeping, so the later report is the one
      # the filter sees.
      record_metrics(device2, %{"cpu_temp" => 36}, DateTime.add(now, -2, :second))
      record_metrics(device2, %{"cpu_temp" => 42, "load_1min" => 3}, now)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> select("Metric", option: "cpu_temp")
      |> choose("Above")
      |> fill_in("Metric value", with: "37")
      # Show only show device2, which has a value greater than 37 on most recent cpu_temp metric.
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
      |> select("Metric", option: "cpu_temp")
      |> choose("Below")
      |> fill_in("Metric value", with: "37")
      # Should not show any device since the query is for values less than 37
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "by custom metrics", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{})

      record_metrics(device2, %{"goats_per_second" => 42})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> open_filters()
      |> select("Metric", option: "goats_per_second")
      |> choose("Above")
      |> fill_in("Metric value", with: "37")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "by metrics compares each device's latest value", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{})

      now = DateTime.utc_now()

      # device: an old high reading superseded by a low one; device2: a high
      # reading, at a different time than device's. Only each device's latest
      # value may count, regardless of which device reported most recently.
      for {reporting, value, seconds_ago} <- [
            {device, 90, 3},
            {device, 30, 2},
            {device2, 60, 1}
          ] do
        record_metrics(reporting, %{"test_latency_ms" => value}, DateTime.add(now, -seconds_ago, :second))
      end

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> open_filters()
      |> select("Metric", option: "test_latency_ms")
      |> choose("Above")
      |> fill_in("Metric value", with: "40")
      # device's latest reading is 30 - its stale 90 must not match.
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
      |> choose("Below")
      # device's latest reading is 30, even though device2 reported later.
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by firmware validation status", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      validated = Fixtures.device_fixture(org, product, firmware, %{})
      not_validated = Fixtures.device_fixture(org, product, firmware, %{})

      set_validation_status(validated, :validated)
      set_validation_status(not_validated, :not_validated)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> open_filters()
      |> pick("firmware_validation_status", "validated", "Validated")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: validated.identifier)
      |> unpick("firmware_validation_status", "validated", "Validated")
      |> pick("firmware_validation_status", "not_validated", "Not validated")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: not_validated.identifier)
      # the fixture device has never reported, so it reads as unknown
      |> unpick("firmware_validation_status", "not_validated", "Not validated")
      |> pick("firmware_validation_status", "unknown", "Unknown")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
    end

    test "by signer CA", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      ca = Fixtures.ca_certificate_fixture(org)
      {:ok, ca_cert} = CACertificates.update_ca_certificate(ca.db_cert, %{description: "Factory signer"})

      signed = Fixtures.device_fixture(org, product, firmware, %{})
      Fixtures.device_certificate_fixture_for_ca(signed, ca)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> open_filters()
      |> select("Signer CA", option: ca_cert.description)
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: signed.identifier)
      |> refute_has("div a", text: device.identifier)
      # the fixture device's certificate was signed by a CA which isn't registered
      |> select("Signer CA", option: "No known CA")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: signed.identifier)
    end

    test "by several tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 =
        Fixtures.device_fixture(org, product, firmware, %{tags: ["filter-test", "test-filter"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> fill_in("#filter-tags", "Tags", with: "filter-test-no-show")
      |> assert_has("#device-count", text: "0", timeout: 1_000)
      |> refute_has("div a", text: device2.identifier)
      |> fill_in("#filter-tags", "Tags", with: "filter-test")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
      |> fill_in("#filter-tags", "Tags", with: "filter-test, test-filter")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device2.identifier)
    end

    test "with no tags", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> fill_in("#filter-tags", "Tags", with: "does_not_matter")
      |> assert_has("#device-count", text: "0", timeout: 1000)
      |> refute_has("div a", text: device2.identifier)
    end

    test "with only untagged", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> assert_has("div a", text: device3.identifier)
      |> open_filters()
      |> check("Untagged only")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device3.identifier)
    end

    test "with alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_alarms_fixture(device, %{"SomeAlarm" => "active"})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> pick("alarm_status", "with", "Any raised")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "without alarms", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_alarms_fixture(device, %{"SomeAlarm" => "active"})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> pick("alarm_status", "without", "None raised")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "with specific alarm", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      alarm = "SomeAlarm"
      Fixtures.device_alarms_fixture(device, %{alarm => "active"})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> pick("alarm", alarm, alarm)
      |> assert_path(device_index_path(fixture), query_params: %{alarm: alarm})
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by deployment group", %{conn: conn, fixture: fixture} do
      %{
        device: device,
        firmware: firmware,
        org: org,
        product: product,
        deployment_group: deployment_group
      } =
        fixture

      device2 = Fixtures.device_fixture(org, product, firmware)

      Repo.update!(Ecto.Changeset.change(device, deployment_id: deployment_group.id))

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> open_filters()
      |> select("Deployment group", option: deployment_group.name)
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> assert_has("div a", text: device.identifier)
      |> refute_has("div a", text: device2.identifier)
    end

    test "by no deployment", %{conn: conn, fixture: %{device: device} = fixture} do
      refute device.deployment_id

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("button", text: "Filters", timeout: 1000)
      |> open_filters()
      |> select("Deployment group", option: "Any")
      |> assert_has("#device-count", text: "1", timeout: 1000)
    end

    test "select device", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> refute_has("#bulk-bar")
      |> check("input#checkbox-device-#{device2.id}", "")
      |> assert_has("#bulk-selected", text: "1 selected")
    end

    test "select/deselect all devices", %{conn: conn, fixture: fixture} do
      %{device: _device, firmware: firmware, org: org, product: product} = fixture

      _device2 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})
      _device3 = Fixtures.device_fixture(org, product, firmware, %{tags: ["foo"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> check("Select all devices")
      |> assert_has("#device-count", text: "3")
      |> assert_has("#bulk-selected", text: "3 selected")
      |> uncheck("Select all devices")
      |> assert_has("#device-count", text: "3")
      |> refute_has("#bulk-bar")
    end

    test "excludes deleted device by default", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000, exact: false)
      |> refute_has("a", text: deleted_device.identifier, timeout: 1000, exact: false)
    end

    test "filter to include deleted devices", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> choose("Include")
      |> assert_has("a", text: device.identifier, timeout: 1000, exact: false)
      |> assert_has("a", text: deleted_device.identifier, exact: false)
    end

    test "filter only deleted devices", %{
      conn: conn,
      fixture: %{device: device, org: org, product: product, firmware: firmware}
    } do
      refute device.deleted_at

      deleted_device =
        Fixtures.device_fixture(org, product, firmware, %{deleted_at: DateTime.utc_now()})

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> choose("Only deleted")
      |> assert_has("a", text: deleted_device.identifier, timeout: 1000, exact: false)
      |> refute_has("a", text: device.identifier, exact: false)
    end

    test "filter only updating devices", %{
      conn: conn,
      fixture: %{
        device: device,
        org: org,
        product: product,
        deployment_group: deployment_group
      }
    } do
      deployment_group = Repo.preload(deployment_group, :org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("a", text: device.identifier, timeout: 1000)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)

      {:ok, _inflight_update} = DeviceEvents.schedule_update(device.id, deployment_group)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> assert_has("a", text: device.identifier, timeout: 1000)

      {:ok, _device} = FirmwareUpdates.firmware_update_successful(device, device.firmware_metadata)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> open_filters()
      |> pick("updates", "updating", "Updating")
      |> refute_has("a", text: device.identifier, timeout: 1000)
    end

    test "using another select drop down filter doesn't reset the deployment group drop down filter", %{
      conn: conn,
      fixture: fixture
    } do
      %{device: device, firmware: firmware, org: org, product: product, deployment_group: deployment_group} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      device3 = Fixtures.device_fixture(org, product, firmware, %{tags: nil})

      Repo.update!(Ecto.Changeset.change(device2, deployment_id: deployment_group.id))
      Repo.update!(Ecto.Changeset.change(device3, deployment_id: deployment_group.id))

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> assert_has("div a", text: device3.identifier)
      |> open_filters()
      |> select("Deployment group", option: deployment_group.name)
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> select("Platform", option: "platform")
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> assert_has("#filter-deployment_id:has(> option[selected])")
    end
  end

  describe "filters panel" do
    # fixture's device: online and unhealthy; healthy: online and healthy;
    # unknown: offline, never reported its health.
    setup %{fixture: %{org: org, product: product, firmware: firmware, device: device}} do
      healthy = Fixtures.device_fixture(org, product, firmware)
      unknown = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(device, %{status: :connected})
      Fixtures.device_connection_fixture(healthy, %{status: :connected})

      {:ok, _} = Health.save_device_health(%{"device_id" => device.id, "status" => "unhealthy"})
      {:ok, _} = Health.save_device_health(%{"device_id" => healthy.id, "status" => "healthy"})

      %{healthy: healthy, unknown: unknown}
    end

    test "widens a filter with each choice, and shows it as a token that removes it", context do
      %{conn: conn, fixture: fixture, healthy: healthy, unknown: unknown} = context

      conn
      |> visit(device_index_path(fixture))
      |> open_filters()
      |> pick("health_status", "unhealthy", "Unhealthy")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> pick("health_status", "healthy", "Healthy")
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("a", text: healthy.identifier)
      |> refute_has("a", text: unknown.identifier)
      |> assert_has("#filters-applied", text: "1 applied")
      |> assert_has("#filter-token-health_status", text: "health: healthy, unhealthy")
      |> click_button("#filter-token-health_status", "health: healthy, unhealthy")
      |> assert_has("#device-count", text: "3", timeout: 1000)
      |> refute_has("#filter-token-health_status")
    end

    test "counts what each choice would give alongside the other filters", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture) <> "?connection=connected")
      |> open_filters()
      |> assert_has("#filter-health_status label", text: "Unhealthy 1", timeout: 1000)
      |> assert_has("#filter-health_status label", text: "Unknown 0")
      # a filter's own choices aren't narrowed by it
      |> assert_has("#filter-connection label", text: "Offline 1")
      |> assert_has("#filter-connection label", text: "Online 2")
      |> assert_has("#filters-total", text: "2 of 3 devices")
    end

    test "lists only the versions a device the other filters allow is running", context do
      %{conn: conn, fixture: fixture, tmp_dir: tmp_dir} = context
      %{device: device, org: org, product: product, user: user} = fixture

      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      newer = Fixtures.firmware_fixture(org_key, product, %{version: "9.0.0", dir: tmp_dir})
      # offline, so the Online filter leaves it out
      Fixtures.device_fixture(org, product, newer)

      conn
      |> visit(device_index_path(fixture) <> "?connection=connected")
      |> open_filters()
      |> assert_has("#filter-firmware_version label", text: device.firmware_metadata.version, timeout: 1000)
      |> refute_has("#filter-firmware_version label", text: "9.0.0")
      |> refute_has("#filter-firmware_version label", text: "Unknown")
      # a chosen version stays, so it can be unchosen
      |> visit(device_index_path(fixture) <> "?connection=connected&firmware_version=9.0.0")
      |> open_filters()
      |> assert_has("#filter-firmware_version label", text: "9.0.0 0", timeout: 1000)
    end

    test "resets the panel's filters but keeps the tab", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture) <> "?state=online&health_status=unhealthy")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> open_filters()
      |> click_button("Reset filters")
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> refute_has("#filter-token-health_status")
    end

    test "Find a filter shows only the filters that match", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> open_filters()
      |> assert_has("#filter-group-status")
      |> fill_in("Find a filter", with: "alarm")
      |> assert_has("#filter-group-alarms #filter-alarm_status")
      |> refute_has("#filter-group-status")
      |> refute_has("#filter-group-alarms label", text: "Metric")
      |> fill_in("Find a filter", with: "zebra")
      |> assert_has("#filter-panel", text: "No filter matches")
    end

    test "keeps a filter set from a link that the panel doesn't offer, as a token", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture) <> "?identifier=#{device.identifier}")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> open_filters()
      |> pick("connection", "connected", "Online")
      |> assert_has("#filter-token-connection", timeout: 1000)
      |> assert_has("#filter-token-identifier", text: "identifier: #{device.identifier}")
      |> assert_has("#device-count", text: "1")
    end

    test "closes", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> open_filters()
      |> assert_has("#filter-panel")
      |> click_button("Done")
      |> refute_has("#filter-panel")
    end
  end

  describe "state tabs" do
    # fixture's device: online and unhealthy; device2: last seen 20 days ago.
    setup %{fixture: %{org: org, product: product, firmware: firmware, device: device}} do
      device2 = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(device, %{status: :connected})

      Fixtures.device_connection_fixture(device2, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -20, :day)
      })

      {:ok, _} = Health.save_device_health(%{"device_id" => device.id, "status" => "unhealthy"})

      %{device2: device2}
    end

    test "count each tab's devices", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#state-tab-all[aria-current=page]", text: "2", timeout: 1000)
      |> assert_has("#state-tab-online", text: "1")
      |> assert_has("#state-tab-attention", text: "2")
      |> assert_has("#state-tab-updating", text: "0")
      |> assert_has("#state-tab-offline", text: "1")
    end

    test "list only the picked tab's devices", %{conn: conn, fixture: fixture, device2: device2} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#state-tab-online", text: "1", timeout: 1000)
      |> click_link("#state-tab-online", "Online")
      |> assert_path(device_index_path(fixture), query_params: %{state: "online"})
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("a", text: device.identifier)
      |> refute_has("a", text: device2.identifier)
      |> assert_has("#state-tab-online[aria-current=page]")
    end

    test "keep the other filters", %{conn: conn, fixture: fixture, device2: device2} do
      {:ok, _} = Devices.update_device(device2, %{tags: ["field"]})

      conn
      |> visit(device_index_path(fixture) <> "?tags=field")
      |> assert_has("#state-tab-all", text: "1", timeout: 1000)
      |> assert_has("#state-tab-online", text: "0")
      |> assert_has("#state-tab-attention", text: "1")
      |> assert_has("#sidebar-filter-button", text: "1")
    end

    test "the Needs attention tab lists why each device needs it", %{conn: conn, fixture: fixture, device2: device2} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture) <> "?state=attention")
      |> assert_has("#attention-list #device-row-#{device.id}",
        text: "Unhealthy · the device didn't say why",
        timeout: 1000
      )
      |> assert_has("#attention-list #device-row-#{device2.id}", text: "Not seen in 20 days")
      |> refute_has("#device-list")
      |> refute_has("button", text: "Columns")
    end

    test "a reason narrows the Needs attention list, and the tabs leave it behind", %{
      conn: conn,
      fixture: fixture,
      device2: device2
    } do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture) <> "?state=attention")
      |> assert_has("#reason-tab-all[aria-current=page]", text: "2", timeout: 1000)
      |> assert_has("#reason-tab-unhealthy", text: "1")
      |> assert_has("#reason-tab-failing", text: "0")
      |> assert_has("#reason-tab-not_seen", text: "1")
      |> click_link("#reason-tab-unhealthy", "Unhealthy")
      |> assert_path(device_index_path(fixture), query_params: %{state: "attention", reason: "unhealthy"})
      |> assert_has("#attention-list #device-row-#{device.id}", timeout: 1000)
      |> refute_has("#attention-list #device-row-#{device2.id}")
      |> assert_has("#state-tab-attention", text: "2")
      |> click_link("#state-tab-all", "All")
      |> assert_path(device_index_path(fixture))
      |> assert_has("#device-list #device-row-#{device2.id}", timeout: 1000)
      |> refute_has("#reason-tabs")
    end

    test "a Needs attention row opens the peek", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture) <> "?state=attention")
      |> assert_has("#device-row-#{device.id}", timeout: 1000)
      |> unwrap(fn view -> view |> element("#device-row-#{device.id}") |> render_click() end)
      |> assert_has("#peek-title", text: device.identifier)
      |> assert_has("#device-row-#{device.id}[data-peeked]")
      |> assert_has("#device-container.lg\\:mr-150")
    end

    test "say so when no device needs attention for a reason", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture) <> "?state=attention&reason=failing")
      |> assert_has("#empty-tab", text: "No devices are failing updates", timeout: 1000)
      |> assert_has("#reason-tab-failing[aria-current=page]", text: "0")
    end

    test "say so when nothing needs attention", %{conn: conn, fixture: fixture, device2: device2} do
      %{device: device} = fixture

      {:ok, _} = Health.save_device_health(%{"device_id" => device.id, "status" => "healthy"})
      Repo.update_all(where(DeviceConnection, device_id: ^device2.id), set: [status: :connected])

      conn
      |> visit(device_index_path(fixture) <> "?state=attention")
      |> assert_has("#empty-tab", text: "Nothing needs attention", timeout: 1000)
      |> assert_has("#state-tab-attention", text: "0")
    end
  end

  describe "peek" do
    # fixture's device: online and unhealthy; device2: last seen 20 days ago.
    setup %{fixture: %{org: org, product: product, firmware: firmware, device: device}} do
      device2 = Fixtures.device_fixture(org, product, firmware)

      Fixtures.device_connection_fixture(device, %{status: :connected})

      Fixtures.device_connection_fixture(device2, %{
        status: :disconnected,
        last_seen_at: DateTime.add(DateTime.utc_now(), -20, :day)
      })

      {:ok, _} =
        Health.save_device_health(%{
          "device_id" => device.id,
          "status" => "unhealthy",
          "status_reasons" => %{"unhealthy" => %{"mem_used_percent" => %{"value" => 97, "threshold" => 90}}}
        })

      %{device2: device2}
    end

    test "a row opens the peek, and its identifier still links to the device", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-row-#{device.id}", timeout: 1000)
      |> assert_has("#device-row-#{device.id} a[href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']")
      |> unwrap(fn view -> view |> element("#device-row-#{device.id}") |> render_click() end)
      |> assert_has("#peek-title", text: device.identifier)
      |> assert_has("#device-row-#{device.id}[data-peeked]")
      |> assert_has("#peek-why", text: "Unhealthy")
      |> assert_has("#peek-why", text: "Mem Used: 97%")
      |> assert_has(
        "#device-peek a[data-peek-open][href='/org/#{org.name}/#{product.name}/devices/#{device.identifier}']"
      )
    end

    test "says how long since a device was seen", %{conn: conn, fixture: fixture, device2: device2} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-row-#{device2.id}", timeout: 1000)
      |> unwrap(fn view -> view |> element("#device-row-#{device2.id}") |> render_click() end)
      |> assert_has("#peek-why", text: "Not seen in 20 days")
    end

    test "the arrow keys move along the page, and escape closes it", %{conn: conn, fixture: fixture, device2: device2} do
      [first, second] = Enum.sort_by([fixture.device, device2], & &1.identifier)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-row-#{first.id}", timeout: 1000)
      |> unwrap(fn view -> view |> element("#device-row-#{first.id}") |> render_click() end)
      |> unwrap(fn view -> view |> element("#device-peek") |> render_hook("peek-move", %{"by" => -1}) end)
      |> assert_has("#peek-title", text: first.identifier)
      |> unwrap(fn view -> view |> element("#device-peek") |> render_hook("peek-move", %{"by" => 1}) end)
      |> assert_has("#peek-title", text: second.identifier)
      |> unwrap(fn view -> view |> element("#device-peek") |> render_hook("peek-move", %{"by" => 1}) end)
      |> assert_has("#peek-title", text: second.identifier)
      |> unwrap(fn view -> view |> element("#device-peek") |> render_hook("close-peek", %{}) end)
      |> refute_has("#device-peek")
    end

    test "only opens on a device the page lists", %{conn: conn, fixture: fixture} do
      %{org: org, user: user} = fixture
      other_product = Fixtures.product_fixture(user, org)
      other_device = Fixtures.device_fixture(org, other_product, fixture.firmware)

      {:ok, view, _html} = live(conn, device_index_path(fixture))
      render_async(view, 300)

      render_click(view, "peek", %{"id" => "#{other_device.id}"})
      refute has_element?(view, "#device-peek")

      render_click(view, "peek", %{"id" => "not-an-id"})
      refute has_element?(view, "#device-peek")
    end

    test "reboots the device", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-row-#{device.id}", timeout: 1000)
      |> unwrap(fn view -> view |> element("#device-row-#{device.id}") |> render_click() end)
      |> click_button("#device-peek button", "Reboot…")
      |> assert_has("#flash-info", text: "Reboot requested for #{device.identifier}")

      assert_receive %Broadcast{event: "reboot"}
    end

    test "won't reboot for a member without the permission", %{conn: conn, fixture: fixture} do
      %{org: org, device: device, user: user} = fixture

      org_user = Accounts.get_org_user!(Scope.put_org(Scope.for_user(user), org), user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, device_index_path(fixture))
      render_async(view, 300)

      view |> element("#device-row-#{device.id}") |> render_click()
      assert has_element?(view, "#device-peek")
      refute has_element?(view, "#device-peek button", "Reboot")

      assert render_click(view, "peek-reboot") =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      refute_received %Broadcast{event: "reboot"}
    end
  end

  describe "customize columns listed" do
    test "all columns are shown, as the default", %{conn: conn, fixture: fixture} do
      %{user: user} = fixture

      assert is_nil(user.display_preferences)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("th", text: "Health")
      |> assert_has("th", text: "Firmware")
      |> assert_has("th", text: "Platform")
      |> assert_has("th", text: "Connection")
      |> assert_has("th", text: "Deployment group")
      |> assert_has("th", text: "Tags")
    end

    test "a column name that's no longer known is skipped", %{conn: conn, fixture: fixture} do
      %{user: user} = fixture

      # As if a column had been removed after these preferences were saved.
      {1, _} =
        Repo.update_all(
          from(u in User,
            where: u.id == ^user.id,
            update: [
              set: [
                display_preferences:
                  fragment(
                    ~s|jsonb_build_object('id', gen_random_uuid(), 'device_list_columns', '["retired_column", "health", "tags"]'::jsonb)|
                  )
              ]
            ]
          ),
          []
        )

      assert %{device_list_columns: [:health, :tags]} = Accounts.get_user!(user.id).display_preferences

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("th", text: "Health")
      |> assert_has("th", text: "Tags")
      |> refute_has("th", text: "Firmware")
      # the show settings button is shown using JS, so no `click_button` is needed
      |> uncheck("Tags")
      |> refute_has("th", text: "Tags", timeout: 1_000)

      # Saving the columns again leaves the stale name behind.
      assert %{device_list_columns: [:health]} = Accounts.get_user!(user.id).display_preferences

      assert ["health"] =
               Repo.one(
                 from(u in User,
                   where: u.id == ^user.id,
                   select: fragment("?->'device_list_columns'", u.display_preferences)
                 )
               )
    end

    for {column, label} <- [
          {:health, "Health"},
          {:firmware, "Firmware"},
          {:platform, "Platform"},
          {:connected_info, "Connection"},
          {:deployment_group, "Deployment group"},
          {:tags, "Tags"}
        ] do
      @column column
      @label label
      @friendly_column_name to_string(@column) |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)

      test "#{column} column can be removed", %{conn: conn, fixture: fixture} do
        %{user: user} = fixture

        assert is_nil(user.display_preferences)

        conn
        |> visit(device_index_path(fixture))
        |> assert_has("#device-count", text: "1", timeout: 1000)
        |> assert_has("th", text: @label)
        # the show settings button is shown using JS, so no `click_button` is needed
        |> uncheck(@friendly_column_name)
        |> refute_has("th", text: @label, timeout: 1_000)
      end

      test "#{column} column can be added", %{conn: conn, fixture: %{user: user} = fixture} do
        assert is_nil(user.display_preferences)

        default_column_payload = %{
          "_target" => [to_string(@column)],
          "connected_info" => "true",
          "deployment_group" => "true",
          "firmware" => "true",
          "health" => "true",
          "platform" => "true",
          "tags" => "true"
        }

        {:ok, _user} =
          ListSettingsSidebar.update_displayed_columns(
            user,
            :device_list_columns,
            Map.put(default_column_payload, to_string(@column), "false")
          )

        conn
        |> visit(device_index_path(fixture))
        |> assert_has("#device-count", text: "1", timeout: 1000)
        |> refute_has("th", text: @label)
        # the show settings button is shown using JS, so no `click_button` is needed
        |> check(@friendly_column_name)
        |> assert_has("th", text: @label, timeout: 1_000)
      end
    end
  end

  describe "bulk actions" do
    test "only devices in the product can be selected", %{conn: conn, fixture: fixture, tmp_dir: tmp_dir} do
      %{org: org, product: product} = fixture

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      other_org_key = Fixtures.org_key_fixture(other_org, other_user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})
      other_device = Fixtures.device_fixture(other_org, other_product, other_firmware)

      assert length(NervesHub.Repo.all(Device)) == 2

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      state = :sys.get_state(view.pid)
      assert length(state.socket.assigns.devices.result) == 1
      assert Enum.empty?(state.socket.assigns.selected_devices)

      assert render_click(view, :select, %{id: "#{other_device.id}"}) =~ "Invalid device selection"

      state = :sys.get_state(view.pid)
      assert Enum.empty?(state.socket.assigns.selected_devices)
    end

    test "users with the :view role cannot select devices", %{
      conn: conn,
      fixture: fixture
    } do
      %{org: org, product: product, device: device, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      state = :sys.get_state(view.pid)
      assert length(state.socket.assigns.devices.result) == 1
      assert Enum.empty?(state.socket.assigns.selected_devices)

      assert render_click(view, :select, %{id: "#{device.id}"}) =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      state = :sys.get_state(view.pid)
      assert Enum.empty?(state.socket.assigns.selected_devices)
    end

    test "users with the :view role cannot select all devices", %{
      conn: conn,
      fixture: fixture
    } do
      %{org: org, product: product, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      state = :sys.get_state(view.pid)
      assert length(state.socket.assigns.devices.result) == 1
      assert Enum.empty?(state.socket.assigns.selected_devices)

      assert render_click(view, "select-all") =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      state = :sys.get_state(view.pid)
      assert Enum.empty?(state.socket.assigns.selected_devices)
    end

    test "users with the :view role have the select checkboxs disabled", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, user: user, device: device} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta")
      |> assert_has("span", text: "beta-edge")
      |> assert_has("#toggle-all[disabled]", timeout: 1_000)
      |> assert_has("#checkbox-device-#{device.id}:disabled")
    end

    test "only products that a user has access to can be selected", %{conn: conn, fixture: fixture} do
      %{org: org, product: product} = fixture

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      state = :sys.get_state(view.pid)
      assert is_nil(state.socket.assigns.target_product)

      assert render_click(view, "target-product", %{
               "product_id" => "#{other_product.id}"
             }) =~ "Invalid product selection"

      state = :sys.get_state(view.pid)
      assert is_nil(state.socket.assigns.target_product)
    end

    test "devices can't be moved to an org where the user only has the :view role", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, device: device, user: user} = fixture

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      {:ok, _} = Accounts.add_org_user(other_org, user, %{role: :view})

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> refute_has("#move_to option", text: other_product.name)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)
      render_click(view, :select, %{id: "#{device.id}"})

      assert render_click(view, "target-product", %{"product_id" => "#{other_product.id}"}) =~
               "Invalid product selection"

      assert render_submit(view, "move-devices-product", %{}) =~ "You haven&#39;t selected a product"

      assert Repo.reload(device).product_id == product.id
    end

    test "devices aren't moved if the user's role in the target org drops after picking it", %{
      conn: conn,
      fixture: fixture
    } do
      %{org: org, product: product, device: device, user: user} = fixture

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      {:ok, org_user} = Accounts.add_org_user(other_org, user, %{role: :manage})

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)
      render_click(view, :select, %{id: "#{device.id}"})

      refute render_click(view, "target-product", %{"product_id" => "#{other_product.id}"}) =~
               "Invalid product selection"

      {:ok, _} = Accounts.change_org_user_role(org_user, :view)

      assert render_submit(view, "move-devices-product", %{}) =~ "Invalid product selection"
      assert Repo.reload(device).product_id == product.id

      render_click(view, "select-all-matching", %{})
      render_click(view, "target-product", %{"product_id" => "#{other_product.id}"})

      assert render_submit(view, "move-devices-product", %{}) =~ "You haven&#39;t selected a product"
      assert Repo.reload(device).product_id == product.id
    end

    test "devices can be moved to another org where the user has the :manage role", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, device: device, user: user} = fixture

      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      other_product = Fixtures.product_fixture(other_user, other_org)
      {:ok, _} = Accounts.add_org_user(other_org, user, %{role: :manage})

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-move", "Move to product")
      |> within("form#product-move", fn session ->
        session
        |> select("Move device(s) to product:", option: other_product.name, exact_option: false)
        |> submit()
      end)
      |> assert_has("div", text: "All selected devices successfully moved to #{other_product.name}")

      assert %{org_id: org_id, product_id: product_id} = Repo.reload(device)
      assert org_id == other_org.id
      assert product_id == other_product.id
    end

    test "users with the :view role cannot select products", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      state = :sys.get_state(view.pid)
      assert is_nil(state.socket.assigns.target_product)

      assert render_click(view, "target-product", %{
               "product_id" => "#{product.id}"
             }) =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      state = :sys.get_state(view.pid)
      assert is_nil(state.socket.assigns.target_product)
    end

    test "changes tags", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta")
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> unwrap(fn view ->
        render_submit(view, "tag-devices", %{"tags" => "moussaka"})
      end)
      |> assert_has("span", text: "moussaka", timeout: 1_000)
    end

    test "adds tags to the selected devices", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> choose("Add")
        |> fill_in("Tags", with: "moussaka")
        |> submit()
      end)
      |> assert_has("div", text: "Tags added to all selected device(s).", timeout: 1_000)

      assert Repo.reload(device).tags == ["beta", "beta-edge", "moussaka"]
    end

    test "removes tags from the selected devices", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("span", text: "beta-edge")
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> choose("Remove")
        |> fill_in("Tags", with: "beta")
        |> submit()
      end)
      |> assert_has("div", text: "Tags removed from all selected device(s).", timeout: 1_000)

      assert Repo.reload(device).tags == ["beta-edge"]
    end

    test "keeps the typed tags when the operation changes", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> fill_in("Tags", with: "moussaka")
        |> choose("Remove")
      end)
      |> assert_has("#input_set_tags[value='moussaka']")
    end

    test "users with the :view role cannot change tags", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      assert render_click(view, "tag-devices", %{"tags" => ["Boop"]}) =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end

    test "users with the :view role cannot select a deployment group", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      assert render_click(view, "target-deployment-group", %{"deployment_group" => ["1"]}) =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end

    test "users with the :view role cannot move devices to another product", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, user: user} = fixture

      scope = Scope.for_user(user) |> Scope.put_org(org)

      org_user = Accounts.get_org_user!(scope, user)
      Accounts.change_org_user_role(org_user, :view)

      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      render_async(view, 300)

      assert render_click(view, "move-devices-product", %{"deployment_group" => ["1"]}) =~
               "Sorry, you don't have the required role" |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end

    test "add multiple devices to deployment",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware,
        deployment_group: deployment_group
      } = fixture

      device2 = Fixtures.device_fixture(org, product, firmware)
      Endpoint.subscribe("device:#{device.id}")
      Endpoint.subscribe("device:#{device2.id}")

      refute device.deployment_id
      refute device2.deployment_id

      conn
      |> visit(
        "/org/#{org.name}/#{product.name}/devices?platform=#{deployment_group.current_release.firmware.platform}"
      )
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-group", "Deployment group")
      |> within("form#deployment-set", fn session ->
        session
        |> select("Set deployment group",
          option: deployment_group.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "All selected devices were added to deployment #{deployment_group.name}")

      assert_receive %{event: "updated"}
      assert_receive %{event: "updated"}

      assert Repo.reload(device) |> Map.get(:deployment_id)
      assert Repo.reload(device2) |> Map.get(:deployment_id)
    end

    test "move multiple devices to a different product",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        user: user,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      second_device = Fixtures.device_fixture(org, product, firmware)

      other_product = Fixtures.product_fixture(user, org)

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-move", "Move to product")
      |> within("form#product-move", fn session ->
        session
        |> select("Move device(s) to product:",
          option: other_product.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "All selected devices successfully moved to #{other_product.name}")
      |> visit("/org/#{org.name}/#{other_product.name}/devices")
      |> assert_has("div", text: "2", timeout: 1000)

      assert Repo.reload(device) |> Map.get(:product_id) == other_product.id
      assert Repo.reload(second_device) |> Map.get(:product_id) == other_product.id
    end

    test "disable updates for multiple devices",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      second_device = Fixtures.device_fixture(org, product, firmware)

      assert device.update_mode == :automatic
      assert second_device.update_mode == :automatic

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Disable updates")
      |> assert_has("div", text: "Disabled updates for 2 selected device(s).")
      |> tap(fn _ ->
        assert Repo.reload(device).update_mode == :off
        assert Repo.reload(second_device).update_mode == :off
      end)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Enable updates")
      |> assert_has("div", text: "Enabled updates for 2 selected device(s).")
      |> tap(fn _ ->
        assert Repo.reload(device).update_mode == :automatic
        assert Repo.reload(second_device).update_mode == :automatic
      end)
    end

    test "remove multiple devices from the penalty box",
         %{conn: conn, fixture: fixture} do
      %{
        device: device,
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      second_device = Fixtures.device_fixture(org, product, firmware)

      assert is_nil(device.updates_blocked_until)
      assert is_nil(second_device.updates_blocked_until)

      Device
      |> where(product_id: ^product.id)
      |> Repo.update_all(set: [updates_blocked_until: DateTime.utc_now()])

      conn
      |> visit("/org/#{org.name}/#{product.name}/devices")
      |> assert_has("div", text: "2", timeout: 1000)
      |> check("Select all devices", exact: false)
      |> assert_has("#bulk-selected", text: "2 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Clear penalty box")
      |> assert_has("div", text: "2 selected device(s) cleared from the penalty box.")

      assert Repo.reload(device).updates_blocked_until |> is_nil()
      assert Repo.reload(second_device).updates_blocked_until |> is_nil()
    end
  end

  describe "pager" do
    setup %{fixture: %{org: org, product: product, firmware: firmware}} do
      %{second_device: Fixtures.device_fixture(org, product, firmware)}
    end

    test "says which devices it shows and pages through them", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture) <> "?page_size=1")
      |> assert_has("#device-pager", text: "1–1 of 2", timeout: 1_000)
      |> assert_has("#device-pager nav", text: "1 / 2")
      |> assert_has("#device-pager button[aria-label='Previous page'][disabled]")
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> assert_has("#device-pager", text: "2–2 of 2", timeout: 1_000)
      |> assert_has("#device-pager nav", text: "2 / 2")
      |> assert_has("#device-pager button[aria-label='Next page'][disabled]")
    end
  end

  describe "phone layout" do
    setup %{fixture: %{org: org, product: product, firmware: firmware}} do
      %{second_device: Fixtures.device_fixture(org, product, firmware)}
    end

    test "Select makes tapping a device select it, until Done", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> refute_has("#phone-selection")
      |> click_button("#phone-select", "Select")
      |> assert_has("#phone-selection", text: "0 selected")
      |> refute_has("#phone-select")
      |> unwrap(&render_click(&1, "peek", %{"id" => device.id}))
      |> refute_has("#device-peek")
      |> assert_has("#phone-selection", text: "1 selected")
      |> assert_has("#checkbox-device-#{device.id}[checked]")
      |> click_button("#phone-selection-done", "Done")
      |> refute_has("#phone-selection")
      |> refute_has("#checkbox-device-#{device.id}[checked]")
      |> unwrap(&render_click(&1, "peek", %{"id" => device.id}))
      |> assert_has("#device-peek")
    end

    test "sorts from the sort menu above the cards", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#phone-list-meta", text: "1–2 of 2", timeout: 1_000)
      |> assert_has("#phone-sort-select option[selected][value='identifier:asc']")
      |> unwrap(&render_change(element(&1, "#phone-sort"), %{"sort" => "connection_established_at:desc"}))
      |> assert_has("#phone-sort-select option[selected][value='connection_established_at:desc']")
      |> unwrap(&render_change(element(&1, "#phone-sort"), %{"sort" => "deleted_at:desc"}))
      |> assert_has("#phone-sort-select option[selected][value='connection_established_at:desc']")
    end

    test "the Filters sheet's button says how many devices it shows", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> click_button("#sidebar-filter-button", "Filters")
      |> assert_has("#filter-panel footer button", text: "Show 2 devices")
    end
  end

  describe "empty and loading states" do
    test "says what removing each filter would bring back", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, device: device} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices?tags=nope&platform=platform")
      |> assert_has("#no-matches", text: "No devices match both filters", timeout: 1_000)
      |> assert_has("#no-matches-remove-tags", text: "tags: nope", timeout: 1_000)
      |> assert_has("#no-matches-remove-tags", text: "1")
      |> assert_has("#no-matches", text: "Removing one of them would bring devices back.")
      # Without the platform, the tag still matches nothing, so it isn't offered.
      |> refute_has("#no-matches-remove-platform")
      |> click_button("#no-matches-remove-tags", "Remove")
      |> assert_has("a", text: device.identifier, timeout: 1_000)
      |> refute_has("#no-matches")
    end

    test "says when removing the one filter wouldn't help either", %{conn: conn, fixture: fixture} do
      %{org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices?state=updating&platform=platform")
      |> assert_has("#no-matches", text: "No devices match this filter", timeout: 1_000)
      |> assert_has("#no-matches", text: "Nothing would show here without it either.", timeout: 1_000)
      |> refute_has("#no-matches-remove-platform")
      |> assert_has("#no-matches-reset", text: "Clear filters")
    end

    test "offers to clear a search that matches nothing", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      |> unwrap(&render_hook(&1, "apply-advanced-query", %{"query" => ~s|identifier like "%no-such-device%"|}))
      |> assert_has("#no-matches-remove-advanced_query", text: "Clear search", timeout: 1_000)
      |> refute_has("#no-matches-reset")
      |> click_button("#no-matches-remove-advanced_query", "Clear")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
    end

    test "shows the first device once it connects", %{conn: conn, user: user, org: org} do
      product = Fixtures.product_fixture(user, org, %{name: "Empty"})
      {:ok, view, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")

      assert render_async(view) =~ "Connect your first device"

      org_key = Fixtures.org_key_fixture(org, user)
      firmware = Fixtures.firmware_fixture(org_key, product)
      device = Fixtures.device_fixture(org, product, firmware)

      send(view.pid, :await_first_device)

      assert render_async(view) =~ device.identifier
    end
  end

  describe "bulk bar" do
    setup %{fixture: %{org: org, product: product, firmware: firmware}} do
      %{second_device: Fixtures.device_fixture(org, product, firmware)}
    end

    test "counts the selection, offers the rest, and clears it", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> refute_has("#bulk-bar")
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> assert_has("#bulk-selected", text: "1 selected")
      |> assert_has("#bulk-select-all", text: "Select all 2")
      |> click_button("#bulk-deselect", "")
      |> refute_has("#bulk-bar")
    end

    test "opens one popover at a time, and closes it again", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-tags", "Tags")
      |> assert_has("#bulk-popover[aria-label='Tags']")
      |> assert_has("#bulk-tags[aria-expanded='true']")
      |> click_button("#bulk-group", "Deployment group")
      |> assert_has("#bulk-popover[aria-label='Deployment group']")
      |> refute_has("#bulk-popover[aria-label='Tags']")
      |> click_button("#bulk-group", "Deployment group")
      |> refute_has("#bulk-popover")
      |> click_button("#bulk-move", "Move to product")
      |> click_button("#bulk-popover button", "Cancel")
      |> refute_has("#bulk-popover")
    end

    test "names the tag change on its button, and closes once it's done", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> fill_in("Tags", with: "moussaka")
        |> assert_has("button[type='submit']", text: "Add to 1 device")
        |> choose("Replace all")
        |> assert_has("button[type='submit'][data-confirm]", text: "Replace on 1 device")
        |> choose("Add")
        |> submit()
      end)
      |> assert_has("div", text: "Tags added to all selected device(s).", timeout: 1_000)
      |> refute_has("#bulk-popover")

      assert "moussaka" in Repo.reload(device).tags
    end

    test "won't take a tag with a space in it", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-tags", "Tags")
      |> fill_in("#input_set_tags", "Tags", with: "two words")
      |> assert_has("#bulk-tag-input p.text-alert", text: "A tag can't contain spaces.")
      |> assert_has("#bulk-tag-input button[type='submit'][disabled]")
    end

    test "adds tags as chips, and applies them with one still being typed", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-tags", "Tags")
      |> assert_has("#bulk-tag-input button[type='submit'][disabled]")
      |> unwrap(&render_hook(&1, "bulk-add-tag", %{"tag" => "alpha"}))
      |> unwrap(&render_hook(&1, "bulk-add-tag", %{"tag" => "beta two"}))
      |> assert_has("#bulk-tag-input [data-tag='alpha']")
      |> assert_has("#bulk-tag-input [data-tag='beta']")
      |> assert_has("#bulk-tag-input [data-tag='two']")
      |> assert_has("#bulk-tag-input input[name='tags'][value='alpha,beta,two']")
      |> refute_has("#bulk-tag-input button[type='submit'][disabled]")
      |> unwrap(&render_click(element(&1, "#bulk-tag-input button[phx-value-tag='two']")))
      |> refute_has("#bulk-tag-input [data-tag='two']")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> fill_in("Tags", with: "gamma")
        |> submit()
      end)
      |> assert_has("div", text: "Tags added to all selected device(s).", timeout: 1_000)
      |> click_button("#bulk-tags", "Tags")
      |> refute_has("#bulk-tag-input [data-tag]")

      tags = Repo.reload(device).tags
      assert "alpha" in tags
      assert "beta" in tags
      assert "gamma" in tags
      refute "two" in tags
    end

    test "says why firmware can't be sent until the list is one platform", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-firmware", "Send firmware")
      |> assert_has("#bulk-firmware-unavailable", text: "Filter the list to one platform first")
      |> refute_has("#push-firmware")
    end

    test "opening the Filters panel closes the popover", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      |> unwrap(&render_change(&1, "select", %{"id" => device.id}))
      |> click_button("#bulk-tags", "Tags")
      |> open_filters()
      |> assert_has("#filter-panel")
      |> refute_has("#bulk-popover")
      |> click_button("#bulk-tags", "Tags")
      |> refute_has("#filter-panel")
    end
  end

  describe "bulk actions after selecting all devices" do
    test "move devices to a different product", %{conn: conn, fixture: fixture} do
      %{user: user, org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware) end)

      other_product = Fixtures.product_fixture(user, org)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-move", "Move to product")
      |> within("form#product-move", fn session ->
        session
        |> select("Move device(s) to product:",
          option: other_product.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "All selected devices successfully moved to the selected product.", timeout: 3_000)
      |> visit("/org/#{org.name}/#{other_product.name}/devices")
      |> assert_has("div", text: "26", timeout: 1000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.product_id == other_product.id end)
    end

    test "remove devices from assigned deployment groups", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware, deployment_group: deployment_group} = fixture

      Repo.delete_all(Device)

      devices =
        Enum.map(1..26, fn _ ->
          Fixtures.device_fixture(org, product, firmware, %{deployment_id: deployment_group.id})
        end)

      assert Enum.all?(devices, fn device -> device.deployment_id == deployment_group.id end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-group", "Deployment group")
      |> click_button("#remove-devices-from-deployment-group", "Remove from group")
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div",
        text: "All devices (26) were successfully removed from their deployment group.",
        timeout: 3_000
      )

      assert Repo.reload(devices) |> Enum.all?(fn device -> is_nil(device.deployment_id) end)
    end

    test "move devices to a different deployment group", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware, deployment_group: deployment_group} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware) end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-group", "Deployment group")
      |> within("form#deployment-set", fn session ->
        session
        |> select("Set deployment group",
          option: deployment_group.name,
          exact_option: false
        )
        |> submit()
      end)
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div",
        text: "All selected devices were successfully assigned to the selected deployment group.",
        timeout: 3_000
      )

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.deployment_id == deployment_group.id end)
    end

    test "changes tags", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware) end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> unwrap(fn view ->
        render_submit(view, "tag-devices", %{"tags" => "moussaka"})
      end)
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "Tags updated on all selected devices (26).", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.tags == ["moussaka"] end)
    end

    test "adds tags", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware) end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> choose("Add")
        |> fill_in("Tags", with: "moussaka")
        |> submit()
      end)
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "Tags added to all selected devices (26).", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.tags == ["beta", "beta-edge", "moussaka"] end)
    end

    test "removes tags", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware) end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-tags", "Tags")
      |> within("form#bulk-tag-input", fn session ->
        session
        |> choose("Remove")
        |> fill_in("Tags", with: "beta")
        |> submit()
      end)
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "Tags removed from all selected devices (26).", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.tags == ["beta-edge"] end)
    end

    test "enables updates", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware, %{update_mode: :off}) end)

      assert Enum.all?(devices, fn device -> device.update_mode == :off end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Enable updates")
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "Enabled updates for #{26} selected device(s).", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.update_mode == :automatic end)
    end

    test "disable updates", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices = Enum.map(1..26, fn _ -> Fixtures.device_fixture(org, product, firmware, %{update_mode: :automatic}) end)

      assert Enum.all?(devices, fn device -> device.update_mode == :automatic end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Disable updates")
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "Disabled updates for 26 selected device(s).", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> device.update_mode == :off end)
    end

    test "clear penalty boxes", %{conn: conn, fixture: fixture} do
      %{org: org, product: product, firmware: firmware} = fixture

      Repo.delete_all(Device)

      devices =
        Enum.map(1..26, fn _ ->
          Fixtures.device_fixture(org, product, firmware, %{updates_blocked_until: DateTime.utc_now()})
        end)

      assert Enum.all?(devices, fn device -> not is_nil(device.updates_blocked_until) end)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("h1", text: "Devices", timeout: 1_000)
      |> assert_has("#device-count", text: "26", timeout: 1_000)
      |> check("Select all devices", exact: false)
      |> click_button("#bulk-select-all", "Select all")
      |> assert_has("#bulk-selected", text: "26 selected")
      |> click_button("#bulk-updates", "Updates")
      |> click_button("Clear penalty box")
      |> assert_has("div", text: "Updating devices, please wait...", timeout: 1_000)
      |> assert_has("div", text: "26 selected device(s) cleared from the penalty box.", timeout: 3_000)

      assert Repo.reload(devices) |> Enum.all?(fn device -> is_nil(device.updates_blocked_until) end)
    end
  end

  describe "pagination" do
    test "one page when there are fewer devices than a page holds", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product
      } = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("#device-pager nav", text: "1 / 1", timeout: 1000)
      |> assert_has("#device-pager button[aria-label='Previous page'][disabled]")
      |> assert_has("#device-pager button[aria-label='Next page'][disabled]")
    end

    test "pagination with more than 25 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..26 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager-size-select option[value='25'][selected]")
      |> assert_has("#device-pager nav", text: "1 / 2")
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> refute_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager nav", text: "2 / 2")
      |> click_button("#device-pager button[aria-label='Previous page']", "")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
    end

    test "pagination with more than 50 devices", %{conn: conn, fixture: fixture} do
      %{
        org: org,
        product: product,
        firmware: firmware
      } = fixture

      for _i <- 1..51 do
        Fixtures.device_fixture(org, product, firmware)
      end

      devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
      [first_device | _] = devices |> Enum.sort_by(& &1.identifier)

      conn
      |> visit(~p"/org/#{org}/#{product}/devices")
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
      |> assert_has("#device-pager nav", text: "1 / 3")
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> assert_has("#device-pager nav", text: "2 / 3", timeout: 1000)
      |> click_button("#device-pager button[aria-label='Next page']", "")
      |> assert_has("#device-pager nav", text: "3 / 3", timeout: 1000)
      |> refute_has("a", text: first_device.identifier)
      |> unwrap(&render_change(element(&1, "#device-pager-size"), %{"page-size" => "50"}))
      |> assert_has("#device-pager nav", text: "1 / 2", timeout: 1000)
      |> assert_has("a", text: first_device.identifier, timeout: 1000)
    end

    test "sets deployment group on devices", %{conn: conn, fixture: fixture} do
      %{device: device, deployment_group: deployment_group} = fixture

      refute device.deployment_id

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1_000)
      # Select the device - this should populate valid deployment groups
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> assert_has("#bulk-selected", text: "1 selected")
      # The "Set deployment group" dropdown should be available
      |> click_button("#bulk-group", "Deployment group")
      |> assert_has("label", text: "Set deployment group")
      # Choose the deployment group and submit
      |> unwrap(fn view ->
        render_change(view, "target-deployment-group", %{"deployment_group" => to_string(deployment_group.id)})
      end)
      |> unwrap(fn view ->
        render_submit(view, "move-devices-deployment-group", %{})
      end)
      |> assert_has("div",
        text: "All selected devices were added to deployment #{deployment_group.name}",
        timeout: 1_000
      )
    end

    test "removes devices from deployment group with badge shown", %{conn: conn, fixture: fixture} do
      %{device: device, deployment_group: deployment_group} = fixture

      # Put the device in the deployment group first
      Repo.update!(Ecto.Changeset.change(device, deployment_id: deployment_group.id))

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1_000)
      # Select the device
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> assert_has("#bulk-selected", text: "1 selected")
      # Should show the deployment group badge since all selected are in the same one
      |> click_button("#bulk-group", "Deployment group")
      |> assert_has("#remove-devices-from-deployment-group", text: "Remove from group")
      |> assert_has("#bulk-popover span", text: deployment_group.name)
      # Click remove (trash icon button)
      |> unwrap(fn view ->
        render_click(view, "remove-devices-from-deployment-group", %{})
      end)
      |> assert_has("div", text: "1 device(s) removed from their deployment group", timeout: 1_000)
    end

    test "disables deployment group dropdown when selecting devices with different platforms", %{
      conn: conn,
      fixture: fixture,
      tmp_dir: tmp_dir
    } do
      %{device: device, org: org, product: product, user: user} = fixture

      # Create a second device on a different platform
      org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir, platform: "other_platform"})
      other_device = Fixtures.device_fixture(org, product, other_firmware)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1_000)
      # Select both devices
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => other_device.id})
      end)
      |> assert_has("#bulk-selected", text: "2 selected")
      # The dropdown should be disabled, saying no group fits
      |> click_button("#bulk-group", "Deployment group")
      |> assert_has("select[disabled]#set_deployment_group")
      |> assert_has("option", text: "No group matches these devices")
    end

    test "sends manual firmware update to devices", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("div a", text: device.identifier, timeout: 1_000)
      # Filter by platform to reveal the firmware push option
      |> open_filters()
      |> select("Platform", option: "platform")
      |> assert_has("#device-count", text: "1", timeout: 1_000)
      # Select the device
      |> unwrap(fn view ->
        render_change(view, "select", %{"id" => device.id})
      end)
      |> assert_has("#bulk-selected", text: "1 selected")
      |> click_button("#bulk-firmware", "Send firmware")
      |> assert_has("#push-firmware")
      # Choose the firmware and submit
      |> unwrap(fn view ->
        render_change(view, "target-firmware", %{"firmware" => firmware.uuid})
      end)
      |> unwrap(fn view ->
        render_submit(view, "push-firmware-to-devices", %{})
      end)
      |> assert_has("div", text: "Firmware update sent to 1 device(s)", timeout: 1_000)
    end
  end

  describe "sorting" do
    test "renders the device list with a non-default sort column", %{conn: conn, fixture: fixture} do
      %{device: device, org: org, product: product} = fixture

      conn
      |> visit(~p"/org/#{org}/#{product}/devices?sort=connection_established_at&sort_direction=desc")
      |> assert_has("a", text: device.identifier, timeout: 1000)
    end
  end

  describe "advanced search" do
    test "renders the search field as a rich text editor", %{conn: conn, fixture: fixture} do
      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", timeout: 1000)
      |> assert_has("#advanced-query-input[contenteditable=true]")
    end

    test "applying a valid query filters the device list and persists the value", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
      |> unwrap(fn view ->
        render_hook(view, "apply-advanced-query", %{"query" => ~s|tags contains "prod"|})
      end)
      |> assert_has(~s|#advanced-query-editor-wrapper[data-value='tags contains "prod"']|, timeout: 1000)
      |> assert_has("#device-count", text: "1")
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "a firmware validation query filters the device list", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      not_validated = Fixtures.device_fixture(org, product, firmware, %{})
      set_validation_status(not_validated, :not_validated)

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> unwrap(fn view ->
        render_hook(view, "apply-advanced-query", %{"query" => ~s|firmware_validation_status = "not_validated"|})
      end)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: not_validated.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "an invalid query shows an inline error and does not change the filter", %{conn: conn, fixture: fixture} do
      %{device: device} = fixture

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> unwrap(fn view ->
        render_hook(view, "apply-advanced-query", %{"query" => ~s|bogus_column = "x"|})
      end)
      |> assert_has("p", text: "not a valid column", timeout: 1000)
      |> assert_has("#device-count", text: "1")
      |> assert_has("div a", text: device.identifier)
    end

    test "free text is applied as a search query and filters the device list", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> unwrap(fn view ->
        render_hook(view, "apply-advanced-query", %{"query" => "prod"})
      end)
      # the free text is rewritten to its query language form
      |> assert_has(~s|#advanced-query-editor-wrapper[data-value='search like "%prod%"']|, timeout: 1000)
      |> assert_has("#device-count", text: "1")
      |> assert_has("div a", text: device2.identifier)
      |> refute_has("div a", text: device.identifier)
    end

    test "free text matching a device identifier finds the device", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      _device2 = Fixtures.device_fixture(org, product, firmware, %{identifier: "some-other-device"})

      conn
      |> visit(device_index_path(fixture))
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> unwrap(fn view ->
        render_hook(view, "apply-advanced-query", %{"query" => device.identifier})
      end)
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
    end

    test "clearing an applied query removes the filter", %{conn: conn, fixture: fixture} do
      %{device: device, firmware: firmware, org: org, product: product} = fixture

      device2 = Fixtures.device_fixture(org, product, firmware, %{tags: ["prod"]})

      conn
      |> visit(~p"/org/#{org}/#{product}/devices?#{%{advanced_query: ~s|tags contains "prod"|}}")
      |> assert_has("#device-count", text: "1", timeout: 1000)
      |> assert_has("div a", text: device2.identifier)
      |> unwrap(fn view ->
        render_hook(view, "clear-advanced-query", %{})
      end)
      |> assert_has("#device-count", text: "2", timeout: 1000)
      |> assert_has("div a", text: device.identifier)
      |> assert_has("div a", text: device2.identifier)
    end
  end

  def device_index_path(%{org: org, product: product}) do
    ~p"/org/#{org}/#{product}/devices"
  end

  defp record_metrics(device, metrics, timestamp \\ DateTime.utc_now()) do
    device_info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    {:ok, _stored} = Metrics.record(device_info, metrics, timestamp)
  end

  defp set_validation_status(device, status) do
    {1, _} = Repo.update_all(where(Device, id: ^device.id), set: [firmware_validation_status: status])
    :ok
  end

  # The Filters button shows once the list has loaded.
  defp open_filters(session) do
    session
    |> assert_has("#sidebar-filter-button", timeout: 1000)
    |> click_button("#sidebar-filter-button", "Filters")
  end

  # Turns one of a Filters panel chip's choices on or off, by its value.
  defp pick(session, key, value, label),
    do: check(session, "#filter-#{key} input[value='#{value}']", label, exact: false)

  defp unpick(session, key, value, label),
    do: uncheck(session, "#filter-#{key} input[value='#{value}']", label, exact: false)
end
