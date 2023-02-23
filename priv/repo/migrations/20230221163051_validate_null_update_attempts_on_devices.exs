defmodule NervesHub.Repo.Migrations.ValidateNullUpdateAttemptsOnDevices do
  use Ecto.Migration

  def change do
    execute "update devices set update_attempts = '{}' where update_attempts is null;", ""

    execute "ALTER TABLE devices VALIDATE CONSTRAINT update_attempts_not_null;", ""

    alter table(:devices) do
      modify :update_attempts, {:array, :utc_datetime}, null: false
    end

    drop constraint(:devices, :update_attempts_not_null)
  end
end
