defmodule NervesHub.Repo.Migrations.AddFirmwareDeltaQueryIndexes do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    # Critical: Index for firmware UUID extraction in delta availability query
    # This enables efficient lookup of source firmware by UUID from device metadata
    create_if_not_exists index(
      "devices",
      ["(firmware_metadata #>> '{uuid}')"],
      name: :devices_firmware_uuid_idx,
      concurrently: true
    )

    # Important: Composite index including status for firmware_delta filtering
    # Helps with queries that check if deltas exist and are completed
    create_if_not_exists index(
      "firmware_deltas",
      [:source_id, :target_id, :status],
      name: :firmware_deltas_source_target_status_idx,
      concurrently: true
    )
  end
end
