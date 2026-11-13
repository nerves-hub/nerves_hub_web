defmodule NervesHub.Repo.Migrations.CreateSlackScriptResults do
  use Ecto.Migration

  def change() do
    # A support script's output, shown only to whoever ran it from Slack,
    # kept briefly so they can share it in the channel.
    create table(:slack_script_results, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:team_id, :string, null: false)
      add(:slack_user_id, :string, null: false)
      add(:device_identifier, :string, null: false)
      add(:script_name, :string, null: false)
      add(:output, :text, null: false)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:slack_script_results, [:user_id]))
    create(index(:slack_script_results, [:inserted_at]))
  end
end
