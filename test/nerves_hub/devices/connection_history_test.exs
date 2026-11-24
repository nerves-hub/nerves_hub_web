defmodule NervesHub.Devices.ConnectionHistoryTest do
  # These tests are not async because they interact with the AnalyticsRepo,
  # which is a ClickHouse database that does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.ConnectionTimeline
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    device = Fixtures.device_fixture(org, product, firmware)

    AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history")

    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_connection_history") end)

    {:ok, %{user: user, org: org, product: product, firmware: firmware, device: device}}
  end

  defp history_for(ref) do
    AnalyticsRepo.all(DeviceConnectionHistory, settings: [final: 1])
    |> Enum.filter(&(&1.ref == ref))
  end

  describe "history is recorded for the connection lifecycle" do
    test "device_connecting/3 records a history row", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)

      assert_eventually([%DeviceConnectionHistory{} = history] = history_for(connection.id))

      assert history.org_id == device.org_id
      assert history.product_id == device.product_id
      assert history.device_id == device.id
      assert is_nil(history.disconnected_at)
    end

    test "records the client library the device connected with", %{device: device} do
      {:ok, connection} =
        Connections.device_connecting(device.org_id, device.product_id, device.id, nil, %{
          lib: "nerves_hub_link",
          lib_version: "2.13.0"
        })

      assert_eventually(
        [%DeviceConnectionHistory{lib: "nerves_hub_link", lib_version: "2.13.0"}] = history_for(connection.id)
      )

      # the rows after it are copied from the connection, so they keep it
      :ok = Connections.device_connected(connection.id)
      :ok = Connections.device_disconnected(connection.id)

      assert_eventually(
        [%DeviceConnectionHistory{lib: "nerves_hub_link", lib_version: "2.13.0", disconnected_at: %DateTime{}}] =
          history_for(connection.id)
      )
    end

    test "records an unknown client library as empty", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)

      assert_eventually([%DeviceConnectionHistory{lib: "", lib_version: ""}] = history_for(connection.id))
    end

    test "device_connected/1 records a history row", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      assert_eventually([_] = history_for(connection.id))

      :ok = Connections.device_connected(connection.id)

      # connecting + connected share the same ref/established_at, so the merged
      # view collapses them to a single row
      assert_eventually([%DeviceConnectionHistory{}] = history_for(connection.id))
    end

    test "device_disconnected/2 records a history row with the disconnect details", %{
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(connection.id)
      :ok = Connections.device_disconnected(connection.id, "Stale connection")

      # all three rows share the merge tree's sorting key, and the disconnect is
      # written last, so the merged view collapses to it
      assert_eventually(
        [%DeviceConnectionHistory{disconnected_reason: "Stale connection"} = history] =
          history_for(connection.id)
      )

      assert history.device_id == device.id
      refute is_nil(history.disconnected_at)
    end

    test "a reconnect closes the connection it replaces, as last seen", %{device: device} do
      {:ok, replaced} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(replaced.id)
      last_seen_at = Connections.get_latest_for_device(device.id).last_seen_at

      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)

      assert_eventually(
        [%DeviceConnectionHistory{disconnected_reason: "Reconnected"} = closed] = history_for(replaced.id)
      )

      assert DateTime.compare(closed.disconnected_at, last_seen_at) == :eq
      assert_eventually([%DeviceConnectionHistory{disconnected_at: nil}] = history_for(connection.id))
    end

    test "a reconnect leaves a connection that already disconnected as it was", %{device: device} do
      {:ok, replaced} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(replaced.id)
      :ok = Connections.device_disconnected(replaced.id, "Manual disconnect")

      {:ok, _connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)

      :ok = Buffer.flush(DeviceConnectionHistory)

      assert [%DeviceConnectionHistory{disconnected_reason: "Manual disconnect"}] = history_for(replaced.id)
    end

    test "device_heartbeat/1 records a history row", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(connection.id)

      :ok = Connections.device_heartbeat(connection.id)

      assert_eventually(history_for(connection.id) != [])
    end

    test "clean_stale_connections/0 records history for connections it marks stale", %{
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(connection.id)

      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
      max_jitter = ceil(jitter / 60)
      stale_time = DateTime.utc_now() |> DateTime.add(-(interval + max_jitter + 2), :minute)

      connection
      |> Ecto.Changeset.change(%{last_seen_at: stale_time})
      |> Repo.update!()

      :ok = Connections.clean_stale_connections()

      assert_eventually(
        Enum.any?(history_for(connection.id), fn h ->
          h.disconnected_reason == "Stale connection"
        end)
      )
    end

    test "clean_stale_connections/0 leaves connections only ClickHouse has open", %{device: device} do
      # Open in ClickHouse, with no Postgres row: a disconnect that was lost
      # before reaching ClickHouse. The hourly analytics pass closes these.
      ref = Ecto.UUID.generate(version: 7)
      last_seen_at = stale_time()

      {:ok, _} =
        %DeviceConnection{
          id: ref,
          org_id: device.org_id,
          product_id: device.product_id,
          device_id: device.id,
          established_at: DateTime.add(last_seen_at, -1, :hour),
          last_seen_at: last_seen_at,
          disconnected_at: nil
        }
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()

      :ok = Connections.clean_stale_connections()

      # allow any (incorrectly) spawned insert to run before asserting absence
      Process.sleep(200)

      refute Enum.any?(history_for(ref), fn h -> not is_nil(h.disconnected_at) end)
    end

    test "no history is recorded when analytics is disabled", %{device: device} do
      original = Application.get_env(:nerves_hub, :analytics_enabled)

      try do
        Application.put_env(:nerves_hub, :analytics_enabled, false)

        {:ok, connection} =
          Connections.device_connecting(device.org_id, device.product_id, device.id)

        # give any (erroneously) spawned task a chance to run before asserting absence
        Process.sleep(200)

        assert history_for(connection.id) == []
      after
        Application.put_env(:nerves_hub, :analytics_enabled, original)
      end
    end
  end

  describe "clean_stale_connections_from_analytics/0" do
    # an open connection is one whose latest history row has no disconnected_at
    defp insert_open_connection(device, last_seen_at) do
      ref = Ecto.UUID.generate(version: 7)

      connection = %DeviceConnection{
        id: ref,
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: DateTime.add(last_seen_at, -1, :hour),
        last_seen_at: last_seen_at,
        disconnected_at: nil
      }

      {:ok, _} =
        connection
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()

      ref
    end

    defp stale_time() do
      interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
      jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)
      max_jitter = ceil(jitter / 60)
      DateTime.add(DateTime.utc_now(), -(interval + max_jitter + 2), :minute)
    end

    test "records a disconnected history row for stale open connections, as last seen", %{device: device} do
      last_seen_at = stale_time()
      ref = insert_open_connection(device, last_seen_at)

      :ok = Connections.clean_stale_connections_from_analytics()

      assert_eventually(
        Enum.any?(history_for(ref), fn h ->
          h.disconnected_reason == "Stale connection" and not is_nil(h.disconnected_at) and
            DateTime.compare(h.disconnected_at, last_seen_at) == :eq
        end)
      )
    end

    test "carries the original connection's ref and established_at forward", %{device: device} do
      last_seen_at = stale_time()
      ref = insert_open_connection(device, last_seen_at)
      [open] = history_for(ref)

      :ok = Connections.clean_stale_connections_from_analytics()

      assert_eventually(
        Enum.any?(history_for(ref), fn h ->
          not is_nil(h.disconnected_at) and h.established_at == open.established_at
        end)
      )
    end

    test "leaves recently seen open connections untouched", %{device: device} do
      ref = insert_open_connection(device, DateTime.add(DateTime.utc_now(), -1, :minute))

      :ok = Connections.clean_stale_connections_from_analytics()

      # allow any (incorrectly) spawned insert to run before asserting absence
      Process.sleep(200)

      refute Enum.any?(history_for(ref), fn h -> not is_nil(h.disconnected_at) end)
    end

    test "ignores connections that are already disconnected", %{device: device} do
      ref = Ecto.UUID.generate(version: 7)
      now = DateTime.utc_now()

      connection = %DeviceConnection{
        id: ref,
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: DateTime.add(now, -2, :hour),
        # stale last_seen_at, but the connection is already closed
        last_seen_at: stale_time(),
        disconnected_at: DateTime.add(now, -1, :hour),
        disconnected_reason: "Original reason"
      }

      {:ok, _} =
        connection
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()

      :ok = Connections.clean_stale_connections_from_analytics()

      Process.sleep(200)

      refute Enum.any?(history_for(ref), fn h -> h.disconnected_reason == "Stale connection" end)
    end
  end

  describe "ConnectionTimeline.load/3" do
    test "reads the device's connections, and the last to end before the span", %{
      device: device,
      org: org,
      product: product,
      firmware: firmware
    } do
      other_device = Fixtures.device_fixture(org, product, firmware)
      now = DateTime.utc_now()
      ago = fn minutes -> DateTime.add(now, -minutes, :minute) end

      insert_history(device, ago.(300), ago.(200), reason: "Stale connection")
      insert_history(device, ago.(150), ago.(100), reason: "Reconnected")
      insert_history(device, ago.(70), nil, network_interface: :wifi, ip_address: "10.0.4.17")
      insert_history(other_device, ago.(100), ago.(70))

      assert_eventually(
        ConnectionTimeline.load(device, ago.(180), now) == %ConnectionTimeline{
          offline: [
            %{from: ago.(200), until: ago.(150), reason: "Stale connection", interface: nil, ip_address: nil},
            %{from: ago.(100), until: ago.(70), reason: "Reconnected", interface: "wifi", ip_address: "10.0.4.17"}
          ],
          reconnects: []
        }
      )
    end
  end

  defp insert_history(device, established_at, disconnected_at, extra \\ []) do
    %DeviceConnection{
      id: Ecto.UUID.generate(),
      org_id: device.org_id,
      product_id: device.product_id,
      device_id: device.id,
      established_at: established_at,
      last_seen_at: disconnected_at || established_at,
      disconnected_at: disconnected_at,
      disconnected_reason: extra[:reason],
      network_interface: extra[:network_interface],
      ip_address: extra[:ip_address]
    }
    |> DeviceConnectionHistory.from_device_connection_changeset()
    |> Ecto.Changeset.apply_changes()
    |> AnalyticsRepo.insert!()
  end
end
