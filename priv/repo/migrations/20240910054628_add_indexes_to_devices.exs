defmodule NervesHub.Repo.Migrations.AddIndexesToDevices do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    create_if_not_exists index("devices", [:product_id], concurrently: true)
    create_if_not_exists index("devices", [:updates_enabled], concurrently: true)
    create_if_not_exists index("devices", ["(firmware_metadata->'version')"], name: :devices_firmware_index, using: "GIN", concurrently: true)
    create_if_not_exists index("devices", ["(firmware_metadata->'platform')"], name: :devices_platform_index, using: "GIN", concurrently: true)
    create_if_not_exists index("devices", ["string_array_to_string(tags, ' ', ' ') gin_trgm_ops"], name: :devices_tags_index, using: "GIN", concurrently: true)
    create_if_not_exists index("devices", ["identifier gin_trgm_ops"], name: :devices_identifier_trgm_index, using: "GIN", concurrently: true)
  end
end
