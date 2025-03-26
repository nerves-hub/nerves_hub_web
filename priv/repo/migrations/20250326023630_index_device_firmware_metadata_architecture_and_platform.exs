defmodule NervesHub.Repo.Migrations.IndexDeviceFirmwareMetadataArchitectureAndPlatform do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index("devices", ["(firmware_metadata #> '{platform}'::text[])"], name: :devices_firmware_plat_path_index, using: "BTREE", concurrently: true)
    create_if_not_exists index("devices", ["(firmware_metadata #> '{architecture}'::text[])"], name: :devices_firmware_arch_path_index, using: "BTREE", concurrently: true)
  end
end
