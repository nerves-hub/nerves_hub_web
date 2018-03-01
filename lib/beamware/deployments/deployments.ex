defmodule Beamware.Deployments do
  import Ecto.Query

  alias Beamware.Deployments.Deployment
  alias Beamware.Repo

  @spec get_deployments_by_tenant(integer()) :: [Deployments.t()]
  def get_deployments_by_tenant(tenant_id) do
    from(
      d in Deployment,
      where: d.tenant_id == ^tenant_id,
      join: f in assoc(d, :firmware),
      preload: [firmware: f]
    )
    |> Repo.all()
  end

  def create_deployment(tenant, params) do
    params = Map.put(params, "status", "inactive")

    tenant
    |> Ecto.build_assoc(:deployments)
    |> Deployment.changeset(params)
    |> Repo.insert()
  end
end
