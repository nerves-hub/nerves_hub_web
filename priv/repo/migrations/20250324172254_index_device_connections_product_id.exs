defmodule NervesHub.Repo.Migrations.IndexDeviceConnectionsProductId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create(index(:device_connections, [:product_id], concurrently: true))
  end
end
