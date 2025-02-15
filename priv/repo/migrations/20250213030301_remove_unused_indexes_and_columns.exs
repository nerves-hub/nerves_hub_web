defmodule NervesHub.Repo.Migrations.RemoveUnusedIndexesAndColumns do
  use Ecto.Migration

  def up do
    drop(index(:devices, [:connection_status]))

    alter table("devics") do
      remove(:connection_status)
      remove(:connection_established_at)
      remove(:connection_disconnected_at)
      remove(:connection_last_seen_at)
      remove(:connection_metadata)
      remove(:connection_types)
    end

    drop(index(:device_connections, [:device_id, :established_at]))
  end

  def down do
    raise "One way migration"
  end
end
