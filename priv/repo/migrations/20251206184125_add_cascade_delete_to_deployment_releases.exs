defmodule NervesHub.Repo.Migrations.AddCascadeDeleteToDeploymentReleases do
  use Ecto.Migration

  def up do
    # Drop the existing foreign key constraint
    drop constraint(:deployment_releases, "deployment_releases_deployment_group_id_fkey")

    # Add it back with cascade delete
    alter table(:deployment_releases) do
      modify :deployment_group_id, references(:deployments, on_delete: :delete_all), null: false
    end
  end

  def down do
    # Drop the cascade delete foreign key constraint
    drop constraint(:deployment_releases, "deployment_releases_deployment_group_id_fkey")

    # Add it back without cascade delete (original state)
    alter table(:deployment_releases) do
      modify :deployment_group_id, references(:deployments), null: false
    end
  end
end
