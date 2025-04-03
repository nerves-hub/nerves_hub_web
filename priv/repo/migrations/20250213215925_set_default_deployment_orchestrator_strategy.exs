defmodule NervesHub.Repo.Migrations.SetDefaultDeploymentOrchestratorStrategy do
  use Ecto.Migration

  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  def change do
    repo().query!("UPDATE deployments SET orchestrator_strategy = 'distributed'")
  end
end
