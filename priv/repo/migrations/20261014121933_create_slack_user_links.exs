defmodule NervesHub.Repo.Migrations.CreateSlackUserLinks do
  use Ecto.Migration

  def change() do
    # A Slack user, in a workspace, who acts as a NervesHub user when they
    # click NervesHub's buttons, as proven by signing in with Slack. Keyed by
    # team id rather than by workspace row, so a link outlives the app being
    # reinstalled.
    create table(:slack_user_links) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:team_id, :string, null: false)
      add(:slack_user_id, :string, null: false)
      add(:slack_name, :string)
      add(:team_name, :string)
      add(:linked_at, :utc_datetime_usec, null: false)

      timestamps()
    end

    create(unique_index(:slack_user_links, [:team_id, :slack_user_id]))
    create(index(:slack_user_links, [:user_id]))
  end
end
