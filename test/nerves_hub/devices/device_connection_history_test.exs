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
        interface: "eth0",
        status: :disconnected
      }

      changes = DeviceConnectionHistory.changeset(connection).changes

      assert changes.org_id == 1
      assert changes.product_id == 2
      assert changes.device_id == 3
      assert changes.established_at == established_at
      assert changes.last_seen_at == last_seen_at
      assert changes.disconnected_at == disconnected_at
      assert changes.disconnected_reason == "Stale connection"
      assert changes.lib == "nerves_hub_link"
      assert changes.lib_version == "2.0.0"
      assert changes.interface == "eth0"
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
        |> DeviceConnectionHistory.changeset()
        |> Map.fetch!(:changes)

      assert changes.ref == ref
    end

    test "the version is derived from the connection's last_seen_at so newer rows win" do
      last_seen_at = ~U[2026-06-20 10:05:00.000000Z]

      connection = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: ~U[2026-06-20 10:00:00.000000Z],
        last_seen_at: last_seen_at
      }

      changes = DeviceConnectionHistory.changeset(connection).changes

      assert changes.version == DateTime.to_unix(last_seen_at)
    end

    test "a later last_seen_at produces a higher version" do
      base = %DeviceConnection{
        id: UUIDv7.generate(),
        org_id: 1,
        product_id: 2,
        device_id: 3,
        established_at: ~U[2026-06-20 10:00:00.000000Z]
      }

      earlier = DeviceConnectionHistory.changeset(%{base | last_seen_at: ~U[2026-06-20 10:00:00Z]})
      later = DeviceConnectionHistory.changeset(%{base | last_seen_at: ~U[2026-06-20 10:05:00Z]})

      assert later.changes.version > earlier.changes.version
    end
  end
end
