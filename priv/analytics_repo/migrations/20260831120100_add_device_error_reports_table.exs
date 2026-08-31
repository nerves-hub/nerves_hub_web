defmodule NervesHub.AnalyticsRepo.Migrations.AddDeviceErrorReportsTable do
  use Ecto.Migration

  def change() do
    options = [
      partition_by: "toDate(timestamp)",
      # Sorted by fingerprint, not by device: the read this table exists to
      # serve is "show me every occurrence of this issue", which the product
      # page's drill-down does on every visit. The device tab's per-device
      # filter is covered by the skip index below.
      order_by: "(product_id, fingerprint, timestamp)",
      # Thirty days, against three for log lines. An error you look into a week
      # later is ordinary; a log line you look at a week later is not. The
      # `error_groups` row outlives this, so counts and first-seen survive it.
      ttl: "toDateTime(timestamp) + toIntervalDay(30)"
    ]

    create table(:device_error_reports,
             primary_key: false,
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")

      add(:org_id, :UInt64)
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)

      # Plain String, unlike its neighbours. Fingerprints are bounded per
      # product but not across a deployment, and LowCardinality stops paying
      # for itself well before that many distinct values.
      add(:fingerprint, :String)

      add(:kind, :"LowCardinality(String)")
      add(:source, :"LowCardinality(String)")

      add(:reason, :string)
      add(:message, :string)

      # JSON, the same choice `device_messages.payload` makes: it renders and
      # greps the same way whichever serializer the device negotiated.
      add(:frames, :string)

      # Where device vitals live -- uptime, reboot count, free memory, signal
      # strength, whatever a given runtime can say about itself. Deliberately
      # not columns: those three are what a BEAM device happens to report, and
      # an ESP32 reporting free heap and RSSI instead would need three more.
      # One extensible bag beats a schema change per client.
      add(:context, :"Map(LowCardinality(String), String)")

      # The exception, and the only device state that is a column. It answers
      # "which release broke this", it is bounded per product so LowCardinality
      # pays off, and the platform fills it in from the connection when a
      # device does not send one -- none of which is true of the rest.
      add(:firmware_uuid, :"LowCardinality(String)")

      add(:payload_bytes, :UInt32)
      add(:truncated, :UInt8)
    end

    # The device tab filters by device_id, which is not in the sort key. Without
    # this, "errors on this device" reads every part in the product's
    # partitions. A bloom filter rather than minmax because device ids
    # interleave freely within a part, so a min/max pair excludes nothing.
    #
    # No MATERIALIZE INDEX: the table is empty at this point.
    execute(
      "ALTER TABLE device_error_reports ADD INDEX device_id_idx device_id TYPE bloom_filter(0.01) GRANULARITY 4",
      "ALTER TABLE device_error_reports DROP INDEX device_id_idx"
    )
  end
end
