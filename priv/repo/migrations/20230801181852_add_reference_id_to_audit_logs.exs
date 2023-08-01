defmodule NervesHub.Repo.Migrations.AddReferenceIdToAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      add(:reference_id, :string)
    end
  end
end
