defmodule NervesHub.Repo.Migrations.UpdateAuditLogResourceTypeForDeploymentGroups do
  use Ecto.Migration

  def up() do
    repo().query!(
      "UPDATE audit_logs SET resource_type = 'Elixir.NervesHub.ManagedDeployments.DeploymentGroup' WHERE resource_type = 'Elixir.NervesHub.Deployments.Deployment'"
    )

    repo().query!(
      "UPDATE audit_logs SET actor_type = 'Elixir.NervesHub.ManagedDeployments.DeploymentGroup' WHERE actor_type = 'Elixir.NervesHub.Deployments.Deployment'"
    )
  end

  def down(), do: raise "One way migration"
end
