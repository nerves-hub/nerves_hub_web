defmodule NervesHub.Repo.Migrations.ChangeUserTokenColumnType do
  use Ecto.Migration

  def up do
    rename table(:user_tokens), :token, to: :old_token

    alter table(:user_tokens) do
      add(:token, :binary)
      add(:context, :string, null: false, default: "api")
    end

    flush()

    repo().query!("UPDATE user_tokens SET context = 'api'")

    create(unique_index(:user_tokens, [:context, :token]))
  end

  def down do
    raise "One way migration"
  end
end
