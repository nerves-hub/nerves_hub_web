defmodule NervesHub.Repo.Migrations.UniqueFirmwareAndTenantKeys do
  use Ecto.Migration

  def change do
    create(unique_index(:firmwares, [:product_id, :uuid], name: :firmwares_product_id_uuid_index))
    create(unique_index(:tenant_keys, [:key]))
  end
end
