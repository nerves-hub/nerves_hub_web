defmodule NervesHub.Repo.Migrations.ChangeUserTokenColumnType do
  use Ecto.Migration

  def up do
    repo().query!("DELETE FROM user_tokens")

    alter table(:user_tokens) do
      remove(:token, :string, null: false)
    end

    flush()

    alter table(:user_tokens) do
      add(:token, :binary, null: false)
      add(:context, :string, null: false)
    end

    create(unique_index(:user_tokens, [:context, :token]))
  end

  def down do
    raise "One way migration"
  end
end
