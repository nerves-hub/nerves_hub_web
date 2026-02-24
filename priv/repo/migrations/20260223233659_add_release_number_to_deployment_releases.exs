defmodule NervesHub.Repo.Migrations.AddReleaseNumberToDeploymentReleases do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:deployment_releases) do
      add :number, :integer, null: true
    end

    repo().all(from(dr in "deployment_releases",
      select: %{
        id: dr.id,
        deployment_group_id: dr.deployment_group_id,
        inserted_at: dr.inserted_at,
        num: fragment("ROW_NUMBER() OVER (PARTITION BY deployment_group_id ORDER BY inserted_at ASC)")
      }
    ))
    |> Enum.each(fn release ->
      query = from(dr in "deployment_releases", where: dr.id == ^release.id)
      {1, nil} = repo().update_all(query, set: [number: release.num])
    end)
  end

  def down do
    alter table(:deployment_releases) do
      remove :number
    end
  end
end
