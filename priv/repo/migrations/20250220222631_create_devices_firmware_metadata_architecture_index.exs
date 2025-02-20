defmodule NervesHub.Repo.Migrations.CreateDevicesFirmwareMetadataArchitectureIndex do
  use Ecto.Migration
  @disable_ddl_transaction true


  def change do
    create_if_not_exists index("devices", ["(firmware_metadata->'architecture')"], name: :devices_architecture_index, using: "GIN", concurrently: true)
  end
end
