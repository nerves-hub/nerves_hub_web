defmodule NervesHubWebCore.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  alias NervesHubWebCore.Accounts.AuditLog.Action

  def change do
    Action.create_type()

    create table(:audit_logs, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(:action, Action.type(), null: false)
      add(:actor_id, :id, null: false)
      add(:actor_type, :string, null: false)
      add(:params, :map, null: false)
      add(:resource_id, :id, null: false)
      add(:resource_type, :string, null: false)

      timestamps(updated_at: false)
    end

    index(:audit_logs, [:actor_id, :actor_type])
    index(:audit_logs, [:resource_type, :resource_id])
  end
end
