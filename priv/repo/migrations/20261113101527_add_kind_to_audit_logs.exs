defmodule NervesHub.Repo.Migrations.AddKindToAuditLogs do
  use Ecto.Migration

  # Nullable with no default, so adding it doesn't rewrite the table. Rows
  # written before it have no kind, and the web UI draws them with a neutral
  # icon.
  def change() do
    alter table(:audit_logs) do
      add(:kind, :string)
    end
  end
end
