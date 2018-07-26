defmodule NervesHubCore.Deployments do
  import Ecto.Query

  alias NervesHubCore.Deployments.Deployment
  alias NervesHubCore.Products.Product
  alias NervesHubCore.Accounts.Tenant
  alias NervesHubCore.Repo
  alias Ecto.Changeset

  @spec get_deployments_by_product(integer()) :: [Deployment.t()]
  def get_deployments_by_product(product_id) do
    from(
      d in Deployment,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
    |> Repo.all()
  end

  @spec get_deployment(Product.t(), String.t()) :: {:ok, Deployment.t()} | {:error, :not_found}
  def get_deployment(%Product{id: product_id}, deployment_id) do
    from(
      d in Deployment,
      where: d.id == ^deployment_id,
      join: f in assoc(d, :firmware),
      where: f.product_id == ^product_id,
      preload: [{:firmware, :product}]
    )
    |> Deployment.with_firmware()
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
