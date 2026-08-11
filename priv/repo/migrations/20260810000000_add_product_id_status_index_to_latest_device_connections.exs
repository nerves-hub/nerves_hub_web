defmodule NervesHub.Repo.Migrations.AddProductIdStatusIndexToLatestDeviceConnections do
  use Ecto.Migration

  def change do
    create index(:latest_device_connections, [:product_id, :status])
  end
end
