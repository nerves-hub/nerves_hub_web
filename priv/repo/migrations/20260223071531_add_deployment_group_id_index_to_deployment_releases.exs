defmodule NervesHub.Repo.Migrations.AddDeploymentGroupIdIndexToDeploymentReleases do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up() do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS deployment_releases_deployment_group_id_inserted_at_idx ON deployment_releases(deployment_group_id, inserted_at DESC);"
    )
  end

  def down() do
    execute("DROP INDEX CONCURRENTLY IF EXISTS deployment_releases_deployment_group_id_inserted_at_idx;")
  end
end
