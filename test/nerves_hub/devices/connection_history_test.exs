defmodule NervesHub.Devices.ConnectionHistoryTest do
  # These tests are not async because they interact with the AnalyticsRepo,
  # which is a ClickHouse database that does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.Connections
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

    test "device_connected/1 records a history row", %{device: device} do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      assert_eventually([_] = history_for(connection.id))

      :ok = Connections.device_connected(connection.id)

      # connecting + connected share the same ref/established_at, so the
      # ReplacingMergeTree may keep both rows until merged; both are present.
      assert_eventually(history_for(connection.id) != [])
    end

    test "device_disconnected/2 records a history row with the disconnect details", %{
      device: device
    } do
      {:ok, connection} = Connections.device_connecting(device.org_id, device.product_id, device.id)
      :ok = Connections.device_connected(connection.id)
      :ok = Connections.device_disconnected(connection.id, "Stale connection")

      assert_eventually(
        Enum.any?(history_for(connection.id), fn h ->
          not is_nil(h.disconnected_at) and h.disconnected_reason == "Stale connection"
        end)
      )
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
      ref = UUIDv7.generate()

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

    test "records a disconnected history row for stale open connections", %{device: device} do
      ref = insert_open_connection(device, stale_time())

      :ok = Connections.clean_stale_connections_from_analytics()

      assert_eventually(
        Enum.any?(history_for(ref), fn h ->
          not is_nil(h.disconnected_at) and h.disconnected_reason == "Stale connection"
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
      ref = UUIDv7.generate()
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

  describe "device_connections_by_date/3" do
    setup %{org: org, product: product, firmware: firmware} do
      device_a = Fixtures.device_fixture(org, product, firmware)
      device_b = Fixtures.device_fixture(org, product, firmware)

      %{device_a: device_a, device_b: device_b}
    end

    # Insert a history row directly so we can control established/disconnected
    # timestamps precisely without relying on the async insert path.
    defp insert_history(device, established_at, disconnected_at) do
      last_seen_at = disconnected_at || DateTime.utc_now()

      connection = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: device.org_id,
        product_id: device.product_id,
        device_id: device.id,
        established_at: established_at,
        last_seen_at: last_seen_at,
        disconnected_at: disconnected_at
      }

      {:ok, _} =
        connection
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> AnalyticsRepo.insert()
    end

    defp days_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :day)

    test "buckets unique connected devices per day across the window", %{
      org: org,
      product: product,
      device_a: device_a,
      device_b: device_b
    } do
      # device_a was connected from 5 days ago until 3 days ago
      insert_history(device_a, days_ago(5), days_ago(3))
      # device_b connected 2 days ago and is still connected
      insert_history(device_b, days_ago(2), nil)

      from = Date.add(Date.utc_today(), -14)
      results = Connections.device_connections_by_date(org.id, product.id, from)

      counts = Map.new(results, fn %{day: day, count: count} -> {day, count} end)

      today = Date.utc_today()

      # device_a present on days -5, -4, -3
      assert counts[Date.add(today, -5)] == 1
      assert counts[Date.add(today, -4)] == 1
      assert counts[Date.add(today, -3)] == 1

      # device_b present on days -2, -1, and today
      assert counts[Date.add(today, -2)] == 1
      assert counts[Date.add(today, -1)] == 1
      assert counts[today] == 1
    end

    test "counts each device once per day even with overlapping connections", %{
      org: org,
      product: product,
      device_a: device_a,
      device_b: device_b
    } do
      # both devices connected today
      insert_history(device_a, days_ago(0), nil)
      insert_history(device_b, days_ago(0), nil)
      # device_a has a second (overlapping) connection today
      insert_history(device_a, days_ago(0), nil)

      from = Date.add(Date.utc_today(), -14)
      results = Connections.device_connections_by_date(org.id, product.id, from)

      counts = Map.new(results, fn %{day: day, count: count} -> {day, count} end)

      # two unique devices, despite three connection rows
      assert counts[Date.utc_today()] == 2
    end

    test "only includes connections for the requested org and product", %{
      org: org,
      product: product,
      device_a: device_a,
      user: user,
      tmp_dir: tmp_dir
    } do
      insert_history(device_a, days_ago(1), nil)

      # a device belonging to a different product should not be counted
      other_org = Fixtures.org_fixture(user, %{name: "other-org"})
      other_product = Fixtures.product_fixture(user, other_org)
      other_org_key = Fixtures.org_key_fixture(other_org, user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})
      other_device = Fixtures.device_fixture(other_org, other_product, other_firmware)
      insert_history(other_device, days_ago(1), nil)

      from = Date.add(Date.utc_today(), -14)
      results = Connections.device_connections_by_date(org.id, product.id, from)

      counts = Map.new(results, fn %{day: day, count: count} -> {day, count} end)

      assert counts[Date.add(Date.utc_today(), -1)] == 1
    end

    test "returns no rows when there is no connection history", %{org: org, product: product} do
      from = Date.add(Date.utc_today(), -14)
      assert Connections.device_connections_by_date(org.id, product.id, from) == []
    end
  end

  describe "device_connections_by_hour/3" do
    setup %{org: org, product: product, firmware: firmware} do
      device_a = Fixtures.device_fixture(org, product, firmware)
      device_b = Fixtures.device_fixture(org, product, firmware)

      %{device_a: device_a, device_b: device_b}
    end

    defp hours_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :hour)

    test "buckets unique connected devices per hour across the window", %{
      org: org,
      product: product,
      device_a: device_a,
      device_b: device_b
    } do
      # device_a was connected from 5 hours ago until 3 hours ago
      insert_history(device_a, hours_ago(5), hours_ago(3))
      # device_b connected 2 hours ago and is still connected
      insert_history(device_b, hours_ago(2), nil)

      from = DateTime.add(DateTime.utc_now(), -24, :hour)
      results = Connections.device_connections_by_hour(org.id, product.id, from)

      counts =
        Map.new(results, fn %{day: hour, count: count} ->
          {NaiveDateTime.truncate(hour, :second), count}
        end)

      hour = fn n ->
        DateTime.utc_now()
        |> DateTime.add(-n, :hour)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> Map.put(:minute, 0)
        |> Map.put(:second, 0)
      end

      # device_a present on the -5, -4 and -3 hour buckets
      assert counts[hour.(5)] == 1
      assert counts[hour.(4)] == 1
      assert counts[hour.(3)] == 1

      # device_b present on the -2, -1 and current hour buckets
      assert counts[hour.(2)] == 1
      assert counts[hour.(1)] == 1
      assert counts[hour.(0)] == 1
    end

    test "counts each device once per hour even with overlapping connections", %{
      org: org,
      product: product,
      device_a: device_a,
      device_b: device_b
    } do
      insert_history(device_a, hours_ago(0), nil)
      insert_history(device_b, hours_ago(0), nil)
      # device_a has a second (overlapping) connection this hour
      insert_history(device_a, hours_ago(0), nil)

      from = DateTime.add(DateTime.utc_now(), -24, :hour)
      results = Connections.device_connections_by_hour(org.id, product.id, from)

      total = results |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)

      # two unique devices, despite three connection rows
      assert total == 2
    end

    test "only includes connections for the requested org and product", %{
      org: org,
      product: product,
      device_a: device_a,
      user: user,
      tmp_dir: tmp_dir
    } do
      insert_history(device_a, hours_ago(1), nil)

      other_org = Fixtures.org_fixture(user, %{name: "other-org-hourly"})
      other_product = Fixtures.product_fixture(user, other_org)
      other_org_key = Fixtures.org_key_fixture(other_org, user, tmp_dir)
      other_firmware = Fixtures.firmware_fixture(other_org_key, other_product, %{dir: tmp_dir})
      other_device = Fixtures.device_fixture(other_org, other_product, other_firmware)
      insert_history(other_device, hours_ago(1), nil)

      from = DateTime.add(DateTime.utc_now(), -24, :hour)
      results = Connections.device_connections_by_hour(org.id, product.id, from)

      # every bucket only ever sees device_a — the other org/product is excluded
      assert Enum.all?(results, &(&1.count == 1))
      refute results == []
    end

    test "returns no rows when there is no connection history", %{org: org, product: product} do
      from = DateTime.add(DateTime.utc_now(), -24, :hour)
      assert Connections.device_connections_by_hour(org.id, product.id, from) == []
    end
  end
end
