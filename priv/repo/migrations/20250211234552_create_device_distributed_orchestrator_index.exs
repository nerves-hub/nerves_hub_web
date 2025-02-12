defmodule Elixir.NervesHub.Repo.Migrations.CreateDeviceDistributedOrchestratorIndex do
  use Ecto.Migration

  def change do
    create index("devices", [:deployment_id, :updates_enabled, :updates_blocked_until])
  end
end
