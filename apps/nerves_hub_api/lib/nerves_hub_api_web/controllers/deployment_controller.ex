defmodule NervesHubAPIWeb.DeploymentController do
  use NervesHubAPIWeb, :controller

  alias NervesHubWebCore.{Deployments, Firmwares}
  alias NervesHubWebCore.Deployments.Deployment

  action_fallback(NervesHubAPIWeb.FallbackController)

  plug(:validate_role, [product: :delete] when action in [:delete])
  plug(:validate_role, [product: :write] when action in [:create, :update])
  plug(:validate_role, [product: :read] when action in [:index, :show])

  @whitelist_fields [:name, :firmware_id, :conditions, :is_active]

  def index(%{assigns: %{product: product}} = conn, _params) do
    deployments = Deployments.get_deployments_by_product(product.id)
    render(conn, "index.json", deployments: deployments)
  end

  def create(%{assigns: %{org: org, product: product, user: user}} = conn, params) do
    case Map.get(params, "firmware") do
      nil ->
        {:error, :no_firmware_uuid}

      uuid ->
        with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
             params <- Map.put(params, "firmware_id", firmware.id),
             params <- whitelist(params, @whitelist_fields),
             {:ok, deployment} <- Deployments.create_deployment(params) do
          audit!(user, deployment, :create, params)

          conn
          |> put_status(:created)
          |> put_resp_header(
            "location",
            Routes.deployment_path(conn, :show, org.name, product.name, deployment.name)
          )
          |> render("show.json", deployment: %{deployment | firmware: firmware})
        end
    end
  end

  def show(%{assigns: %{org: _org, product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name) do
      render(conn, "show.json", deployment: deployment)
    end
  end

  def update(%{assigns: %{product: product, user: user}} = conn, %{
        "name" => name,
        "deployment" => deployment_params
      }) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name),
         {:ok, deployment_params} <- update_params(product, deployment_params),
         deployment_params <- whitelist(deployment_params, @whitelist_fields),
         {:ok, %Deployment{} = updated_deployment} <-
           Deployments.update_deployment(deployment, deployment_params) do
      audit!(user, deployment, :update, deployment_params)
      render(conn, "show.json", deployment: updated_deployment)
    end
  end

  def delete(%{assigns: %{product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment} <- Deployments.get_deployment_by_name(product, name),
         {:ok, _deployment} <- Deployments.delete_deployment(deployment) do
      send_resp(conn, :no_content, "")
    end
  end

  defp update_params(product, %{"firmware" => uuid} = params) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:ok, Map.put(params, "firmware_id", firmware.id)}
    end
  end

  defp update_params(_, params), do: {:ok, params}
end
