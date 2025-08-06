defmodule NervesHub.Repo.Migrations.AddActorIndexToAuditLogs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:audit_logs, [:actor_type, :actor_id], concurrently: true)
  end
end
