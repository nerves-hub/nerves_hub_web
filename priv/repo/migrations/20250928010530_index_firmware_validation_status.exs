defmodule NervesHub.Repo.Migrations.IndexFirmwareValidationStatus do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS devices_firmware_validation_status_idx ON devices(firmware_validation_status);"
    )
  end

  def down() do
    execute("DROP INDEX CONCURRENTLY IF EXISTS devices_firmware_validation_status_idx;")
  end
end
