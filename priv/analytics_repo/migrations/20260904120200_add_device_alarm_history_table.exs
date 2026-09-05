defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceAlarmHistoryTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # A device's alarm timeline is the read: "this device, this alarm, in
      # order" answers how long an episode lasted, and the same prefix without
      # the alarm gives the whole device's history. Product leads because every
      # read is product-scoped, as with `device_metrics`.
      order_by: "(product_id, device_id, alarm, timestamp)",
      # Longer than the thirty days `device_metrics` and `device_error_reports`
      # keep. Only transitions are written, so a quarter of alarm history is a
      # rounding error next to a day of metrics, and "has this alarm ever fired
      # on this fleet" is a question worth being able to answer.
      ttl: "toDateTime(timestamp) + toIntervalDay(90)"
    ]

    create table(:device_alarm_history,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      # Without the `Elixir.` prefix, matching `device_alarms` in PostgreSQL.
      # A product raises the same handful of alarm names forever, which is what
      # LowCardinality is for.
      add(:alarm, :"LowCardinality(String)")

      # "raised" or "resolved". Transitions rather than episodes: a row per
      # edge is append-only, which is what `NervesHub.Analytics.Buffer` batches
      # and what MergeTree wants. Episode duration is a window function over
      # the pair.
      add(:event, :"LowCardinality(String)")

      # Carried on the raise; a resolve has nothing new to say about it.
      add(:description, :String)
    end
  end
end
