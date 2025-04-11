defmodule NervesHub.Repo.Migrations.ChangeUserTokenColumnType do
  use Ecto.Migration

  def change do
    rename table(:user_tokens), :token, to: :old_token

    alter table(:user_tokens) do
      add(:token, :binary)
      add(:context, :string, null: false, default: "api")
    end

    create(unique_index(:user_tokens, [:context, :token]))
  end
end
