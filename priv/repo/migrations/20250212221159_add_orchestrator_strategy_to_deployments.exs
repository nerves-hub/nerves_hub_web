defmodule NervesHub.Repo.Migrations.AddOrchestratorStrategyToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:orchestrator_strategy, :string)
    end
  end
end
