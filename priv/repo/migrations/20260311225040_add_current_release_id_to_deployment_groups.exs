defmodule NervesHub.Repo.Migrations.AddCurrentReleaseIDToDeploymentGroups do
  use Ecto.Migration

  import Ecto.Query

  def change() do
    alter table(:deployments) do
      add(:current_deployment_release_id, references(:deployment_releases))
    end

    flush()

    from(dr in "deployment_releases",
      distinct: [:deployment_group_id, desc: dr.number],
      select: %{
        id: dr.id,
        deployment_group_id: dr.deployment_group_id
      },
      order_by: [:deployment_group_id, desc: dr.number]
    )
    |> repo().all()
    |> Enum.each(fn release ->
      query = from(dg in "deployments", where: dg.id == ^release.deployment_group_id)
      {1, nil} = repo().update_all(query, set: [current_deployment_release_id: release.id])
    end)
  end
end
