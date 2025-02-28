defmodule NervesHub.Repo.Migrations.RemoveOrchestratorStrategy do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      remove(:orchestrator_strategy, :string)
    end
  end
end
