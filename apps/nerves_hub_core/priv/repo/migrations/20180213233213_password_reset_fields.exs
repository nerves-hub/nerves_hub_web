defmodule NervesHubCore.Repo.Migrations.PasswordResetFields do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :password_reset_token, :uuid
      add :password_reset_token_expires, :utc_datetime
    end
  end

  def down do
    alter table(:users) do
      remove :password_reset_token
      remove :password_reset_token_expires
    end
  end
end
