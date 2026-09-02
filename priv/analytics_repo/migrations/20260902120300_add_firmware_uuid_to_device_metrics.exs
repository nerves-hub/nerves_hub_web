defmodule NervesHub.AnalyticsRepo.Migrations.AddFirmwareUuidToDeviceMetrics do
  use Ecto.Migration

  def change() do
    # Which firmware the device was running when it took the reading, so a
    # metric can be read per release: whether memory use went up with 1.4.0,
    # whether a temperature regression followed a deploy.
    #
    # Deliberately not part of the sort key. The read this table exists to serve
    # is one device's range of one metric over time, which the health tab does
    # on every visit, and putting the firmware ahead of `device_id` would
    # scatter that range across the part. Grouping a whole product by release
    # scans that product's partitions either way, since it wants every device.
    #
    # A column added after the fact rather than a change to the create: existing
    # rows read as the default until a part is rewritten, which is what
    # ClickHouse does for a new column anyway, and no reading already stored
    # knows which firmware produced it.
    alter table(:device_metrics) do
      add(:firmware_uuid, :"LowCardinality(String)")
    end
  end
end
