defmodule NervesHub.Repo.Migrations.AddActiveDeploymentReleaseIdToDeployments do
  use Ecto.Migration

  def change do
    alter table(:deployments) do
      add(:active_deployment_release_id, references(:deployment_releases))
    end
  end
end
