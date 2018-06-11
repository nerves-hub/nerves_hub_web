defmodule NervesHub.Deployments do
  import Ecto.Query

  alias NervesHub.Deployments.Deployment
  alias NervesHub.Accounts.Tenant
  alias NervesHub.Repo
  alias Ecto.Changeset

  @spec get_deployments_by_tenant(integer()) :: [Deployment.t()]
  def get_deployments_by_tenant(tenant_id) do
    from(
      d in Deployment,
      where: d.tenant_id == ^tenant_id,
      join: f in assoc(d, :firmware),
      preload: [firmware: f]
    )
    |> Repo.all()
  end

  @spec get_deployment(Tenant.t(), String.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment(%Tenant{id: tenant_id}, deployment_id) do
    from(
      d in Deployment,
      where: d.tenant_id == ^tenant_id,
      where: d.id == ^deployment_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      deployment ->
        {:ok, deployment}
    end
  end

  @spec delete_deployment(Deployment.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def delete_deployment(%Deployment{id: deployment_id}) do
    Repo.get!(Deployment, deployment_id)
    |> Repo.delete()
    |> case do
      {:error, _changeset} ->
        {:error, :not_found}

      {:ok, deployment} ->
        {:ok, deployment}
    end
  end

  @spec update_deployment(Deployment.t(), map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def update_deployment(deployment, params) do
    deployment
    |> Deployment.edit_changeset(params)
    |> Repo.update()
  end

  @spec create_deployment(map) :: {:ok, Deployment.t()} | {:error, Changeset.t()}
  def create_deployment(params) do
    %Deployment{}
    |> Deployment.changeset(params)
    |> Repo.insert()
  end
end
