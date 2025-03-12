defmodule NervesHub.Repo.Migrations.AddDeviceConnectionLastSeenAtIndexes do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute("CREATE INDEX CONCURRENTLY device_connections_not_connected_last_seen_idx ON device_connections(last_seen_at) WHERE status <> 'connected';")
    execute("CREATE INDEX CONCURRENTLY device_connections_connected_last_seen_at_idx ON device_connections(last_seen_at) WHERE status = 'connected';")
  end
end
