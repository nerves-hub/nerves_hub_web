defmodule NervesHub.Devices.DeviceConnectionHistoryTest do
  # Pure changeset mapping, no database access required.
  use ExUnit.Case, async: true

  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceConnectionHistory

  describe "changeset/1" do
    test "maps the fields from a device connection onto the history record" do
      established_at = ~U[2026-06-20 10:00:00.000000Z]
      last_seen_at = ~U[2026-06-20 10:05:00.000000Z]
      disconnected_at = ~U[2026-06-20 10:10:00.000000Z]
      ref = UUIDv7.generate()

      connection = %DeviceConnection{
        id: ref,
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: established_at,
        last_seen_at: last_seen_at,
        disconnected_at: disconnected_at,
        disconnected_reason: "Stale connection",
        lib: "nerves_hub_link",
        lib_version: "2.0.0",
        network_interface: "eth0",
        status: :disconnected
      }

      changes = DeviceConnectionHistory.from_device_connection_changeset(connection).changes

      assert changes.org_id == 1
      assert changes.product_id == 2
      assert changes.device_id == 3
      assert changes.established_at == established_at
      assert changes.last_seen_at == last_seen_at
      assert changes.disconnected_at == disconnected_at
      assert changes.disconnected_reason == "Stale connection"
      assert changes.lib == "nerves_hub_link"
      assert changes.lib_version == "2.0.0"
      assert changes.network_interface == "eth0"
      assert changes.ref == ref
    end

    test "the ref points back to the originating connection's id" do
      ref = UUIDv7.generate()

      changes =
        %DeviceConnection{
          id: ref,
          org_id: 1,
          product_id: 2,
          device_id: 3,
          established_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now()
        }
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> Map.fetch!(:changes)

      assert changes.ref == ref
    end

    test "the version is set from the insert time so the most recently written row wins" do
      connection = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        # an old last_seen_at must not drag the version backwards
        established_at: ~U[2020-01-01 00:00:00.000000Z],
        last_seen_at: ~U[2020-01-01 00:05:00.000000Z]
      }

      one_second = 1_000_000
      before = System.system_time(:microsecond)
      changes = DeviceConnectionHistory.from_device_connection_changeset(connection).changes

      # version tracks the current time at insert, independent of last_seen_at -
      # it can sit a hair past the clock when a tie has to be broken, so the
      # upper bound is loose
      assert changes.version >= before
      assert changes.version <= before + one_second
    end

    test "successive rows for the same connection get strictly increasing versions" do
      connection = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: DateTime.utc_now(),
        last_seen_at: DateTime.utc_now()
      }

      # every row for a connection shares the ReplacingMergeTree's sorting key,
      # so the versions have to break the tie - ties are resolved arbitrarily by
      # ClickHouse and the disconnect could lose to an earlier row
      versions =
        Enum.map(1..25, fn _ ->
          DeviceConnectionHistory.from_device_connection_changeset(connection).changes.version
        end)

      assert versions == Enum.sort(versions)
      assert versions == Enum.uniq(versions)
    end

    test "the version does not depend on last_seen_at" do
      base = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: ~U[2026-06-20 10:00:00.000000Z]
      }

      now = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
      one_second = 1_000_000

      old_last_seen =
        DeviceConnectionHistory.from_device_connection_changeset(%{base | last_seen_at: ~U[2020-01-01 00:00:00Z]})

      new_last_seen =
        DeviceConnectionHistory.from_device_connection_changeset(%{base | last_seen_at: ~U[2026-06-20 10:05:00Z]})

      # both are versioned by insert time, not by their (very different) last_seen_at
      assert_in_delta old_last_seen.changes.version, now, 2 * one_second
      assert_in_delta new_last_seen.changes.version, now, 2 * one_second
    end

    test "mark_as_stale_and_disconnected_changeset bumps the version past the row it carries forward" do
      ref = UUIDv7.generate()

      # version the carried forward row the way the writer would have, so the
      # bump has to beat it even when both land in the same microsecond
      carried_forward_version =
        %DeviceConnection{
          id: ref,
          org_id: 1,
          product_id: 2,
          device_id: 3,
          established_at: ~U[2026-06-20 10:00:00.000000Z],
          last_seen_at: ~U[2026-06-20 10:05:00.000000Z]
        }
        |> DeviceConnectionHistory.from_device_connection_changeset()
        |> Map.fetch!(:changes)
        |> Map.fetch!(:version)

      history = %DeviceConnectionHistory{
        org_id: 1,
        product_id: 2,
        device_id: 3,
        ref: ref,
        established_at: ~U[2026-06-20 10:00:00.000000Z],
        last_seen_at: ~U[2026-06-20 10:05:00.000000Z],
        version: carried_forward_version
      }

      changes = DeviceConnectionHistory.mark_as_stale_and_disconnected_changeset(history).changes

      assert changes.disconnected_reason == "Stale connection"
      assert changes.version > history.version
    end
  end
end
