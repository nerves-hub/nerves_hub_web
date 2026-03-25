defmodule NervesHub.Repo.Migrations.AddDeviceConnectionsStatusLastSeenIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:device_connections, [:status, :last_seen_at],
      concurrently: true,
      name: :device_connections_status_last_seen_at_index
    )
  end
end
