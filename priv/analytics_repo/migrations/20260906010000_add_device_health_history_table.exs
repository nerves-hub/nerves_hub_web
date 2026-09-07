defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceHealthHistoryTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # A device's health timeline is the read: "this device, in order" gives
      # the transitions, and how long a level held is the gap to the next row.
      # Product leads because every read is product-scoped, as with
      # `device_metrics` and `device_alarm_history`.
      order_by: "(product_id, device_id, timestamp)",
      # Matching `device_alarm_history` rather than the thirty days
      # `device_metrics` keeps. Only transitions are written, so a quarter of
      # health history costs less than a day of readings — and outliving the
      # readings is the point: past the metrics TTL this table is the only
      # thing that can still say what a device's status was.
      ttl: "toDateTime(timestamp) + toIntervalDay(90)"
    ]

    create table(:device_health_history,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      # "unknown", "healthy", "warning" or "unhealthy" — four values for the
      # life of the table, which is what LowCardinality is for.
      add(:status, :"LowCardinality(String)")

      # The engaged levels and what engaged them, as the JSON stored on
      # `device_health.status_reasons`; empty when no level is engaged. Kept
      # rather than recomputed because it names the threshold and period in
      # force at the time, which is what makes a row still true after somebody
      # edits the profile.
      add(:status_reasons, :String)
    end
  end
end
