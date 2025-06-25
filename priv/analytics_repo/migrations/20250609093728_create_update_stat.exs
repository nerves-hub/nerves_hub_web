defmodule NervesHub.AnalyticsRepo.Migrations.CreateUpdateStat do
  use Ecto.Migration

  def change do
    create table(:update_stats,
             primary_key: false,
             engine: "MergeTree",
             options: [
               partition_by: "deployment_id",
               # becomes primary key
               order_by: "(product_id, deployment_id, device_id, timestamp)",
             ]
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)
      add(:deployment_id, :UInt64)
      add(:type, :"LowCardinality(String)")
      add(:source_firmware_uuid, :"Nullable(UUID)")
      add(:target_firmware_uuid, :UUID)
      add(:update_bytes, :UInt64)
      add(:saved_bytes, :Int64)
    end
  end
end
