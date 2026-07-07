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

      before = DateTime.utc_now() |> DateTime.to_unix()
      changes = DeviceConnectionHistory.from_device_connection_changeset(connection).changes
      later = DateTime.utc_now() |> DateTime.to_unix()

      # version tracks the current time at insert, independent of last_seen_at
      assert changes.version >= before
      assert changes.version <= later
    end

    test "the version does not depend on last_seen_at" do
      base = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: ~U[2026-06-20 10:00:00.000000Z]
      }

      now = DateTime.utc_now() |> DateTime.to_unix()

      old_last_seen =
        DeviceConnectionHistory.from_device_connection_changeset(%{base | last_seen_at: ~U[2020-01-01 00:00:00Z]})

      new_last_seen =
        DeviceConnectionHistory.from_device_connection_changeset(%{base | last_seen_at: ~U[2026-06-20 10:05:00Z]})

      # both are versioned by insert time, not by their (very different) last_seen_at
      assert_in_delta old_last_seen.changes.version, now, 2
      assert_in_delta new_last_seen.changes.version, now, 2
    end
  end
end
