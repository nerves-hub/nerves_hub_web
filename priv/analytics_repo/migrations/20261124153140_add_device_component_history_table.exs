defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceComponentHistoryTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # The read is one component's timeline, for the Recent list on its
      # panel, and the same prefix without the serial gives the device's.
      # Product leads because every read is product-scoped.
      order_by: "(product_id, device_id, namespace, serial, timestamp)",
      # As long as alarm history: only changes are written, and a gateway's
      # sensors change rarely.
      ttl: "toDateTime(timestamp) + toIntervalDay(90)"
    ]

    create table(:device_component_history,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      add(:namespace, :"LowCardinality(String)")
      add(:serial, :String)

      # "appeared", "missing", "returned", "firmware_changed" or "forgotten".
      add(:event, :"LowCardinality(String)")

      # For "missing", "unreachable" or "unlisted". For "firmware_changed",
      # the version it moved from. Empty otherwise.
      add(:detail, :String)

      # The firmware the component reported at the time.
      add(:firmware_version, :String)
    end
  end
end
