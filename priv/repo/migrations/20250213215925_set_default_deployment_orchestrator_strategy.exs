defmodule NervesHub.Repo.Migrations.SetDefaultDeploymentOrchestratorStrategy do
  use Ecto.Migration

  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.Repo

  def change do
    Repo.update_all(DeploymentGroup, set: [orchestrator_strategy: "distributed"])
  end
end
