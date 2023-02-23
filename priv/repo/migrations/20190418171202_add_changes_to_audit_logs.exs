defmodule NervesHub.Repo.Migrations.AddChangesToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add(:changes, :map)
    end
  end
end
