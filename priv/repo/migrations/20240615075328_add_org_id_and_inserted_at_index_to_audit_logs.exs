defmodule NervesHub.Repo.Migrations.AddOrgIdAndInsertedAtIndexToAuditLogs do
  use Ecto.Migration
  @disable_ddl_transaction true

  def change do
    create index("audit_logs", [:org_id, :inserted_at], concurrently: true)
  end
end
