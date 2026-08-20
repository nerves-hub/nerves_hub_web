defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceMessagesTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      order_by: "(product_id, device_id, timestamp)",
      ttl: "toDateTime(timestamp) + toIntervalDay(3)"
    ]

    create table(:device_messages,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      add(:direction, :"LowCardinality(String)")
      add(:topic, :"LowCardinality(String)")
      add(:event, :"LowCardinality(String)")

      add(:payload, :string)
      add(:payload_bytes, :UInt32)
      add(:truncated, :UInt8)
    end
  end
end
