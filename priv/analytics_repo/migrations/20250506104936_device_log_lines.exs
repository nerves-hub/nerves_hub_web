defmodule NervesHub.AnalyticsRepo.Migrations.DeviceLogLines do
  use Ecto.Migration

  def change do
    options = [
      partition_by: "toDate(timestamp)",
      order_by: "(product_id, device_id, timestamp)",
      ttl: "toDateTime(timestamp) + toIntervalDay(3)"
    ]

    create table(:device_log_lines,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)
      add(:level, :"LowCardinality(String)")
      add(:message, :string)
      add(:meta, :"Map(LowCardinality(String), String)")
    end
  end
end
