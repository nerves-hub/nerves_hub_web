defmodule NervesHubWebCore.Repo.Migrations.AddIndexesToAuditLogs do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:audit_logs, [:resource_type, :resource_id], concurrently: true)
  end
end
