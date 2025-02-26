defmodule NervesHub.Repo.Migrations.SetDefaultDeploymentOrchestratorStrategy do
  use Ecto.Migration

  alias NervesHub.Deployments.Deployment
  alias NervesHub.Repo

  def change do
    Repo.update_all(Deployment, set: [orchestrator_strategy: "multi"])
  end
end
