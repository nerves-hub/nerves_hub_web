defmodule NervesHub.Repo.Migrations.NullTrueOnActionAndParamsForAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      modify(:action, :action, null: true)
      modify(:params, :jsonb, null: true)
    end
  end
end
