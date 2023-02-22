defmodule NervesHubWebCore.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    create table(:user_tokens) do
      add :token, :string
      add :note, :string
      add :last_used, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:user_tokens, :token)
  end
end
