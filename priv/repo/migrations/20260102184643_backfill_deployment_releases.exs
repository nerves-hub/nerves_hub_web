defmodule NervesHub.Repo.Migrations.BackfillDeploymentReleases do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Find all deployment groups that don't have any releases
    deployment_groups_without_releases =
      repo().all(from(dg in "deployments",
        left_join: dr in "deployment_releases",
        on: dr.deployment_group_id == dg.id,
        where: is_nil(dr.id),
        select: %{
          id: dg.id,
          firmware_id: dg.firmware_id,
          archive_id: dg.archive_id
        }
      ))

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Create a deployment release for each deployment group without one
    # created_by_id is null since these are system-backfilled, not user-created
    deployment_releases = Enum.map(deployment_groups_without_releases, fn dg ->
      %{
        deployment_group_id: dg.id,
        firmware_id: dg.firmware_id,
        archive_id: dg.archive_id,
        created_by_id: nil,
        inserted_at: now,
        updated_at: now
      }
    end)

    if deployment_releases != [] do
      repo().insert_all("deployment_releases", deployment_releases)
    end
  end

  def down do
    :ok
  end
end
