defmodule NervesHub.Repo.Migrations.SetDefaultDeploymentOrchestratorStrategy do
  use Ecto.Migration

  alias NervesHub.Deployments.Deployment
  alias NervesHub.Repo

  def change do
    repo().query!("UPDATE deployments SET orchestrator_strategy = 'multi'")
  end
end
