defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceUpdateHistoryTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # "This device, in order" gives one device's update record, which is the
      # read behind a penalty box investigation. Product leads because every
      # read is product-scoped, as with `device_metrics`, `device_alarm_history`
      # and `device_health_history`.
      order_by: "(product_id, device_id, timestamp)",
      # A year, where the other history tables keep ninety days. One row per
      # finished update attempt is orders of magnitude rarer than a health
      # transition — a fleet that updates monthly writes one row per device per
      # month — so a year of it costs less than a week of metrics, and firmware
      # rollouts are compared across releases rather than across days.
      ttl: "toDateTime(timestamp) + toIntervalDay(365)"
    ]

    create table(:device_update_history,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      # The deployment group that asked for the update, or 0 for one a user
      # pushed by hand. ClickHouse has no null-by-default, and every other id
      # column here is a plain UInt64, so the absence is a zero rather than a
      # Nullable(UInt64) that costs a second column to store.
      add(:deployment_id, :UInt64)

      # How the attempt ended: "succeeded", "failed", "ignored", "rescheduled",
      # "expired" or "abandoned". Six values for the life of the table, which is
      # what LowCardinality is for. `NervesHub.Devices.UpdateHistory` documents
      # what each one means and which of them count as a failure.
      add(:status, :"LowCardinality(String)")

      # The firmware the device was running when the attempt started, and the
      # one it was being moved to. Stored as the uuids rather than firmware ids
      # because firmware rows are deletable and these must stay readable after
      # one goes; `update_stats` records them the same way.
      add(:source_firmware_uuid, :String)
      add(:target_firmware_uuid, :String)

      # What the device said, where it said anything — the reason carried on a
      # "failed", "ignored" or "rescheduled" report. Empty otherwise.
      add(:reason, :String)
    end
  end
end
