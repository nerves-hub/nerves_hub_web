defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceMetricsTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # Device before key, both under product. The two reads this serves are
      # "this device, this key, over the last few hours" (the health tab's
      # charts) and "this device, everything, latest" -- both walk a single
      # device's range, and the chart read narrows to one key inside it.
      order_by: "(product_id, device_id, key, timestamp)",
      # Thirty days, matching `device_error_reports`. Deliberately not
      # `HEALTH_CHECK_DAYS_TO_RETAIN`: a ClickHouse TTL is fixed when the table
      # is created, so it cannot follow a runtime setting the way the old
      # PostgreSQL truncation worker did. That setting keeps governing
      # `device_health`, which is still truncated in PostgreSQL.
      ttl: "toDateTime(timestamp) + toIntervalDay(30)"
    ]

    create table(:device_metrics,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      # Both carried on the row rather than joined back to PostgreSQL. Every
      # read is already scoped to a product, and `DeviceInfo` has both to hand
      # on the write path, so denormalising them costs nothing and saves the
      # one join ClickHouse cannot do.
      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      # Metric names are device-defined -- the health tab renders whatever
      # arrives -- so this cannot be a column per metric. LowCardinality suits
      # the shape anyway: a product reports the same dozen names forever, and
      # `NervesHub.Devices.Metrics` caps both the length and the number of
      # names a device may introduce.
      add(:key, :"LowCardinality(String)")

      add(:value, :Float64)
    end
  end
end
