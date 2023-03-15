defmodule NervesHub.Repo.Migrations.SetInsertedAtUsecOnAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      modify(:inserted_at, :utc_datetime_usec)
    end
  end
end
