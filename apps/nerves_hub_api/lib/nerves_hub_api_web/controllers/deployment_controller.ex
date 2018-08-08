defmodule NervesHubAPIWeb.DeploymentController do
  use NervesHubAPIWeb, :controller

  alias NervesHubCore.{Deployments, Firmwares}
  alias NervesHubCore.Deployments.Deployment

  action_fallback NervesHubAPIWeb.FallbackController

  def index(%{assigns: %{product: product}} = conn, _params) do
    deployments = Deployments.get_deployments_by_product(product.id)
    render(conn, "index.json", deployments: deployments)
  end

  def show(%{assigns: %{tenant: tenant, product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name) do
      render(conn, "show.json", deployment: deployment)
    end
  end

  def update(%{assigns: %{product: product, tenant: tenant}} = conn, %{"name" => name, "deployment" => deployment_params}) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name),
        {:ok, deployment_params} <- update_params(tenant, deployment_params),
        {:ok, %Deployment{} = deployment} <- Deployments.update_deployment(deployment, deployment_params) do
      
      render(conn, "show.json", deployment: deployment)
    end
  end

  defp update_params(tenant, %{"firmware" => uuid} = params) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(tenant, uuid) do
      {:ok, Map.put(params, "firmware_id", firmware.id)}
    end
  end

  defp update_params(_, params), do: {:ok, params}
end
