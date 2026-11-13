defmodule NervesHub.Repo.Migrations.CreateSlackWorkspaces do
  use Ecto.Migration

  def change() do
    # A Slack workspace NervesHub's app is installed in, and the one bot token
    # Slack issues for it.
    create table(:slack_workspaces) do
      add(:team_id, :string, null: false)
      add(:team_name, :string, null: false)
      add(:enterprise_id, :string)
      add(:app_id, :string, null: false)
      add(:bot_user_id, :string, null: false)
      add(:bot_token, :binary, null: false)
      add(:scopes, {:array, :string}, null: false, default: [])

      timestamps()
    end

    create(unique_index(:slack_workspaces, [:team_id]))

    # An organization connected to a workspace. A workspace can be connected
    # to more than one organization.
    create table(:slack_connections) do
      add(:org_id, references(:orgs, on_delete: :delete_all), null: false)
      add(:workspace_id, references(:slack_workspaces, on_delete: :delete_all), null: false)
      add(:connected_by_id, references(:users, on_delete: :nilify_all))

      timestamps()
    end

    create(unique_index(:slack_connections, [:org_id, :workspace_id]))
    create(index(:slack_connections, [:workspace_id]))
    create(index(:slack_connections, [:connected_by_id]))
  end
end
