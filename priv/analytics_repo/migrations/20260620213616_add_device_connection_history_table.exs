defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceConnectionHistoryTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(established_at)",
      order_by: "(org_id, product_id, device_id, established_at)"
    ]

    create table(:device_connection_history,
             primary_key: false,
             engine: "ReplacingMergeTree(version)",
             options: options
           ) do
      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      add(:established_at, :"DateTime64(6, 'UTC')")
      add(:last_seen_at, :"DateTime64(6, 'UTC')")
      add(:disconnected_at, :"Nullable(DateTime64(6, 'UTC'))")

      add(:disconnected_reason, :"LowCardinality(String)")

      add(:ref, :UUID)

      add(:lib, :"LowCardinality(String)")
      add(:lib_version, :"LowCardinality(String)")

      add(:interface, :"LowCardinality(String)")

      add(:version, :UInt64)
    end
  end
end
