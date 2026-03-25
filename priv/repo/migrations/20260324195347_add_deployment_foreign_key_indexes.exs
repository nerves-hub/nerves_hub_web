defmodule NervesHub.Repo.Migrations.AddDeploymentForeignKeyIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Index for join from deployment_groups to deployment_releases
    create_if_not_exists index(:deployments, [:current_deployment_release_id],
             concurrently: true,
             name: :deployments_current_release_id_index
           )

    # Index for join from deployment_releases to firmwares
    create_if_not_exists index(:deployment_releases, [:firmware_id],
             concurrently: true,
             name: :deployment_releases_firmware_id_index
           )

    # Index for join from deployment_releases to archives
    create_if_not_exists index(:deployment_releases, [:archive_id],
             concurrently: true,
             name: :deployment_releases_archive_id_index
           )
  end
end
