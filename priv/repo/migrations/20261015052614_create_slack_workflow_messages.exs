defmodule NervesHub.Repo.Migrations.CreateSlackWorkflowMessages do
  use Ecto.Migration

  def change() do
    # The Slack messages with buttons for a deployment workflow step (Approve,
    # Retry, Skip), kept so they can be edited once the step is dealt with.
    create table(:slack_workflow_messages) do
      add(:subscription_id, references(:slack_subscriptions, on_delete: :delete_all), null: false)
      add(:channel_id, :string, null: false)
      add(:ts, :string, null: false)
      add(:type, :string, null: false)
      add(:events, {:array, :map}, null: false)
      add(:step_ids, {:array, :bigint}, null: false)
      # By step id: what was done to it and by whom.
      add(:resolutions, :map, null: false, default: %{})

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:slack_workflow_messages, [:subscription_id]))
    create(index(:slack_workflow_messages, [:step_ids], using: :gin))
    create(index(:slack_workflow_messages, [:channel_id, :ts]))
    create(index(:slack_workflow_messages, [:inserted_at]))
  end
end
