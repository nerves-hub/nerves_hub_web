defmodule NervesHub.Repo.Migrations.AddFirmwareIdIndexToDeviceFirmwares do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    # A firmware's page counts the devices that have ever installed it. Include
    # `device_id` so the count can be answered from the index alone.
    create(index(:device_firmwares, [:firmware_id, :device_id], concurrently: true))
  end
end
