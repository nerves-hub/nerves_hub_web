defmodule NervesHubWebCore.Repo.Migrations.DefaultNullUpdateAttemptsOnDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      modify :update_attempts, {:array, :utc_datetime}, default: fragment("'{}'")
    end

    create constraint(:devices, :update_attempts_not_null, check: "update_attempts is not null", validate: false)
  end
end
