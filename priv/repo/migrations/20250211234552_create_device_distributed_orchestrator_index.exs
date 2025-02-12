defmodule Elixir.NervesHub.Repo.Migrations.CreateDeviceDistributedOrchestratorIndex do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      modify :updates_blocked_until, :utc_datetime, default: fragment("'-infinity'")
    end

    create index(:devices, [:deployment_id, :updates_enabled, :updates_blocked_until])
  end

  def down do
    alter table(:devices) do
      modify :updates_blocked_until, :utc_datetime, default: nil
    end

    drop index(:devices, [:deployment_id, :updates_enabled, :updates_blocked_until])
  end
end
