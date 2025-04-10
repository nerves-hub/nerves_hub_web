defmodule NervesHub.Repo.Migrations.ChangeUserTokenColumnType do
  use Ecto.Migration

  def change do
    alter table(:user_tokens) do
      modify(:token, :binary)
      add(:context, :string, null: false, default: "api")
    end

    create(unique_index(:user_tokens, [:context, :token]))
  end
end
