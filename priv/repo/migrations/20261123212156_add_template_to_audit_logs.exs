defmodule NervesHub.Repo.Migrations.AddTemplateToAuditLogs do
  use Ecto.Migration

  def change() do
    alter table(:audit_logs) do
      add(:template, :text)
      add(:template_values, :map)
    end
  end
end
