defmodule NervesHub.AnalyticsRepo.Migrations.CreateUpdateStat do
  use Ecto.Migration

  def change do
    options = [
      partition_by: "deployment_id"
    ]

    create table(:device_stats,
             primary_key: "(product_id, deployment_id, device_id, timestamp)",
             engine: "MergeTree",
             options: options
           ) do
      add(:timestamp, :"DateTime64(6, 'UTC')")
      add(:product_id, :UInt64)
      add(:device_id, :UInt64)
      add(:deployment_id, :UInt64)
      add(:type, :"LowCardinality(String)")
      add(:update_bytes, :UInt64)
      add(:saved_bytes, :Int64)
    end
  end
end
