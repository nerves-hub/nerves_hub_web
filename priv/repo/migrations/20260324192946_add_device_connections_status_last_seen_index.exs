defmodule NervesHub.Repo.Migrations.AddDeviceConnectionsStatusLastSeenIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:device_connections, [:status, :last_seen_at], concurrently: true)
  end
end
