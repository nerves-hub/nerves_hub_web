defmodule NervesHub.Repo.Migrations.AddPlatformAndArchitectureToDeploymentGroups do
  use Ecto.Migration

  import Ecto.Query

  def change() do
    alter table(:deployments) do
      add(:platform, :string, null: true)
      add(:architecture, :string, null: true)
    end

    flush()

    from(dg in "deployments",
      join: cr in "deployment_releases",
      on: cr.id == dg.current_deployment_release_id,
      join: f in "firmwares",
      on: f.id == cr.firmware_id,
      select: %{deployment_group_id: dg.id, firmware_platform: f.platform, firmware_architecture: f.architecture}
    )
    |> repo().all()
    |> Enum.each(fn firmware_info ->
      query = from(dg in "deployments", where: dg.id == ^firmware_info.deployment_group_id)

      {1, nil} =
        repo().update_all(query,
          set: [platform: firmware_info.firmware_platform, architecture: firmware_info.firmware_architecture]
        )
    end)
  end
end
