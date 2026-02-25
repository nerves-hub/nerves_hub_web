defmodule NervesHub.Repo.Migrations.SetDefaultDeploymentOrchestratorStrategy do
  use Ecto.Migration

  def change do
    repo().query!("UPDATE deployments SET orchestrator_strategy = 'distributed'")
  end
end
