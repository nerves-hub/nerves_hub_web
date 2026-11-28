defmodule NervesHubWeb.Live.Devices.Show.ComponentsTabTest do
  use NervesHubWeb.ConnCase.Browser, async: false

  import Ecto.Query

  alias NervesHub.Accounts.OrgUser
  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Components
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceComponent
  alias NervesHub.Devices.DeviceComponentHistory
  alias NervesHub.Products.Product
  alias NervesHub.Repo

  setup %{product: product, device: device} do
    AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
    AnalyticsRepo.query!("TRUNCATE TABLE device_component_readings")

    on_exit(fn ->
      AnalyticsRepo.query!("TRUNCATE TABLE device_component_history")
      AnalyticsRepo.query!("TRUNCATE TABLE device_component_readings")
    end)

    {:ok, product} = product |> Product.changeset(%{"extensions" => %{"components" => true}}) |> Repo.update()

    %{product: product, device: %{device | product: product}}
  end

  defp components_path(org, product, device),
    do: "/org/#{org.name}/#{product.name}/devices/#{device.identifier}/components"

  defp sync(device, components) do
    info = %DeviceInfo{
      device_id: device.id,
      device_identifier: device.identifier,
      org_id: device.org_id,
      product_id: device.product_id
    }

    now = DateTime.utc_now()
    {:ok, entries} = Components.parse(components, now)
    :ok = Components.sync_snapshot(info, entries, now)
  end

  @mcu %{
    "namespace" => "mcu",
    "vendor" => "raspberrypi",
    "model" => "rp2350",
    "serial" => "e6614c311b4a2c2f",
    "name" => "Sensor board",
    "versions" => %{"firmware" => "1.4.2"}
  }

  @door %{
    "namespace" => "zigbee",
    "vendor" => "1286",
    "model" => "SNZB-04P",
    "serial" => "00:12:4b:00:2a:3f:91:c7",
    "name" => "Dock door",
    "vendor_name" => "Sonoff",
    "reachable" => false
  }

  test "isn't a tab for a product without components", %{conn: conn, org: org, device: device} = context do
    {:ok, product} = context.product |> Product.changeset(%{"extensions" => %{"components" => false}}) |> Repo.update()

    conn
    |> visit("/org/#{org.name}/#{product.name}/devices/#{device.identifier}")
    |> refute_has("a", text: "Components")
    |> visit(components_path(org, product, device))
    |> assert_has("div", text: "Components aren't enabled for this product.")
  end

  test "says when the device has turned components off", %{conn: conn, org: org, product: product, device: device} do
    {:ok, _device} = device |> Device.changeset(%{"extensions" => %{"components" => false}}) |> Repo.update()
    assert %{extensions: %{components: false}} = Repo.reload!(device)

    conn
    |> visit(components_path(org, product, device))
    |> assert_has("div", text: "Components aren't enabled for this device.")
  end

  test "before the first snapshot", %{conn: conn, org: org, product: product, device: device} do
    conn
    |> visit(components_path(org, product, device))
    |> assert_has("span", text: "No components yet.")
  end

  test "lists components by namespace, with why one is missing", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    sync(device, [@mcu, @door])

    conn
    |> visit(components_path(org, product, device))
    |> assert_has("a", text: "Components")
    |> assert_has("#components-list td", text: "MCU")
    |> assert_has("#components-list td", text: "Zigbee")
    |> assert_has("#components-list", text: "Sensor board")
    |> assert_has("#components-list", text: "Sonoff SNZB-04P")
    |> assert_has("#components-list", text: "Can't reach it since")
    |> assert_has("#components-list span", text: "Working")
    |> assert_has("#components-list span", text: "Missing")
  end

  test "without a time from the device, a missing component shows when it went missing", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    sync(device, [@door])

    conn
    |> visit(components_path(org, product, device))
    |> assert_has("#components-list td", text: "Just now")
  end

  test "without a time from the device, a working component shows when the device was last seen", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    {:ok, _connection} = Connections.device_connecting(device.org_id, device.product_id, device.id, "198.51.100.2")
    sync(device, [@mcu])

    conn
    |> visit(components_path(org, product, device))
    |> assert_has("#components-list td", text: "Just now")
  end

  test "Needs attention shows only what's missing", %{conn: conn, org: org, product: product, device: device} do
    sync(device, [@mcu, @door])

    conn
    |> visit(components_path(org, product, device))
    |> click_button("Needs attention")
    |> assert_has("#components-list", text: "Dock door")
    |> refute_has("#components-list", text: "Sensor board")
  end

  test "remembers the grid view", %{conn: conn, org: org, product: product, device: device} do
    sync(device, [@mcu])

    conn
    |> visit(components_path(org, product, device))
    |> unwrap(&render_click(&1, "set-component-view", %{"view" => "grid"}))
    |> assert_has("#components-grid", text: "Sensor board")
    |> visit(components_path(org, product, device))
    |> assert_has("#components-grid")
  end

  test "opens a component in the side panel", %{conn: conn, org: org, product: product, device: device} do
    sync(device, [@door])
    [door] = Components.list_for_device(device)

    conn
    |> visit(components_path(org, product, device) <> "?component=#{door.id}")
    |> assert_has("#component-panel h2", text: "Dock door")
    |> assert_has("#component-why", text: "The device can't reach this component.")
    |> assert_has("#component-panel dd", text: "00:12:4b:00:2a:3f:91:c7")
  end

  test "the panel shows every version a component holds, and when one changed", %{
    conn: conn,
    org: org,
    product: product,
    device: device
  } do
    sync(device, [%{@mcu | "versions" => %{"firmware" => "1.4.2", "sensor_model" => "2026.10"}}])
    sync(device, [%{@mcu | "versions" => %{"firmware" => "1.4.2", "sensor_model" => "2026.11"}}])
    :ok = Buffer.flush(DeviceComponentHistory)
    [mcu] = Components.list_for_device(device)

    conn
    |> visit(components_path(org, product, device) <> "?component=#{mcu.id}")
    |> assert_has("#component-panel dd", text: "1.4.2")
    |> assert_has("#component-version-sensor_model dd", text: "2026.11")
    |> assert_has("#component-history", text: "sensor_model 2026.10 → 2026.11", timeout: 2000)
  end

  test "forgets a component", %{conn: conn, org: org, product: product, device: device} do
    sync(device, [@door])
    [door] = Components.list_for_device(device)

    conn
    |> visit(components_path(org, product, device) <> "?component=#{door.id}")
    |> click_button("Forget component")
    |> assert_has("span", text: "No components yet.")

    assert Components.list_for_device(device) == []
  end

  test "a new snapshot shows without a reload", %{conn: conn, org: org, product: product, device: device} do
    session = visit(conn, components_path(org, product, device))

    sync(device, [@mcu])

    assert_has(session, "#components-list", text: "Sensor board")
  end

  describe "readings and state" do
    @lock %{
      "namespace" => "zwave",
      "vendor" => "0129",
      "model" => "8002:0600",
      "serial" => "34028-23669",
      "name" => "Office lock",
      "state" => %{"lock" => "unlocked"}
    }

    defp record_readings(device, serial, metrics) do
      info = %DeviceInfo{device_id: device.id, org_id: device.org_id, product_id: device.product_id}
      now = DateTime.utc_now()

      report = %{
        "namespace" => "zigbee",
        "serial" => serial,
        "timestamp" => DateTime.to_iso8601(now),
        "metrics" => metrics
      }

      Components.record_readings(info, Components.parse_readings([report], now))
    end

    test "the list shows a component's state, or its readings", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      sync(device, [@lock, %{@door | "reachable" => true}])
      record_readings(device, @door["serial"], %{"temperature" => -18.4, "battery" => 87})

      conn
      |> visit(components_path(org, product, device))
      |> assert_has("#components-list td", text: "Unlocked")
      |> assert_has("#components-list td", text: "-18.4")
      |> assert_has("#components-list td", text: "°C")
    end

    test "the panel shows state and readings", %{conn: conn, org: org, product: product, device: device} do
      sync(device, [%{@lock | "namespace" => "zigbee"}])
      record_readings(device, @lock["serial"], %{"battery" => 18})
      [lock] = Components.list_for_device(device)

      conn
      |> visit(components_path(org, product, device) <> "?component=#{lock.id}")
      |> assert_has("#component-state", text: "Unlocked")
      |> assert_has("#component-readings #component-reading-battery", text: "18")
    end

    test "a reading with nothing in ClickHouse says so rather than loading for good", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      sync(device, [%{@door | "reachable" => true}])
      [door] = Components.list_for_device(device)

      # The latest value is on the row, but no reading reached ClickHouse.
      {1, _} =
        Repo.update_all(where(DeviceComponent, id: ^door.id),
          set: [readings: %{"battery" => %{"value" => 87.0, "at" => DateTime.to_iso8601(DateTime.utc_now())}}]
        )

      conn
      |> visit(components_path(org, product, device) <> "?component=#{door.id}")
      |> assert_has("#component-reading-battery", text: "Not enough to draw yet", timeout: 2000)
    end

    test "changes close together are one re-read, and the last still shows", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      sync(device, [@lock])
      session = visit(conn, components_path(org, product, device))
      info = %DeviceInfo{device_id: device.id, org_id: device.org_id, product_id: device.product_id}

      for value <- ["jammed", "locked", "unlocked", "open"] do
        :ok =
          Components.record_state(info, %{
            "namespace" => "zwave",
            "serial" => "34028-23669",
            "state" => "lock",
            "value" => value
          })
      end

      assert_has(session, "#components-list td", text: "Open", timeout: 2000)
    end

    test "a state change shows without a reload", %{conn: conn, org: org, product: product, device: device} do
      sync(device, [@lock])
      session = visit(conn, components_path(org, product, device))

      info = %DeviceInfo{device_id: device.id, org_id: device.org_id, product_id: device.product_id}

      :ok =
        Components.record_state(info, %{
          "namespace" => "zwave",
          "serial" => "34028-23669",
          "state" => "lock",
          "value" => "jammed"
        })

      assert_has(session, "#components-list td", text: "Jammed")
    end

    test "an open panel shows a state change once it has been written", %{
      conn: conn,
      org: org,
      product: product,
      device: device
    } do
      sync(device, [@lock])
      [lock] = Components.list_for_device(device)
      session = visit(conn, components_path(org, product, device) <> "?component=#{lock.id}")

      info = %DeviceInfo{device_id: device.id, org_id: device.org_id, product_id: device.product_id}

      :ok =
        Components.record_state(info, %{
          "namespace" => "zwave",
          "serial" => "34028-23669",
          "state" => "lock",
          "value" => "jammed",
          "detail" => "by keypad, user 3"
        })

      assert_has(session, "#component-history", text: "Jammed by keypad, user 3", timeout: 3000)
    end
  end

  describe "a member with the view role" do
    setup do
      Repo.update_all(OrgUser, set: [role: :view])

      :ok
    end

    test "sees the panel but can't forget or ask again", %{conn: conn, org: org, product: product, device: device} do
      sync(device, [@door])
      [door] = Components.list_for_device(device)

      session =
        conn
        |> visit(components_path(org, product, device) <> "?component=#{door.id}")
        |> assert_has("#component-panel h2", text: "Dock door")
        |> refute_has("button", text: "Forget component")
        |> refute_has("button", text: "look again")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(unwrap(session, fn view -> render_click(view, "forget-component", %{"id" => door.id}) end))

      assert [_] = Components.list_for_device(device)
    end
  end
end
