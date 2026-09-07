defmodule NervesHub.Repo.Migrations.AddProductIdStatusIndexToLatestDeviceConnections do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change() do
    create(index(:latest_device_connections, [:product_id, :status], concurrently: true))
  end
end
