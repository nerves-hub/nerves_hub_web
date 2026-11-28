defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceComponentReadingsTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # As `device_metrics`, with the component between the device and the
      # key: the read is one component's readings over the last few hours, for
      # the sparklines on its panel.
      order_by: "(product_id, device_id, namespace, serial, key, timestamp)",
      # Thirty days, as `device_metrics`.
      ttl: "toDateTime(timestamp) + toIntervalDay(30)"
    ]

    create table(:device_component_readings,
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

      # Names come from the device, as metric names do, and are capped the
      # same way: at most twenty per report, of at most 64 characters.
      add(:key, :"LowCardinality(String)")
      add(:value, :Float64)

      # What the device was running when the reading was taken, and what the
      # component said it was running, so a reading can be read per release
      # of either.
      add(:firmware_uuid, :"LowCardinality(String)")
      add(:firmware_version, :"LowCardinality(String)")
    end
  end
end
