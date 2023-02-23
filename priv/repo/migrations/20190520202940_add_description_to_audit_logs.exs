defmodule NervesHub.Repo.Migrations.AddDescriptionToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add(:description, :string)
    end
  end
end
