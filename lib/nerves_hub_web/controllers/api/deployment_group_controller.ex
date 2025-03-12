defmodule NervesHubWeb.API.DeploymentGroupController do
  use NervesHubWeb, :api_controller

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  action_fallback(NervesHubWeb.API.FallbackController)

  plug(:validate_role, [org: :manage] when action in [:create, :update, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  @whitelist_fields [:name, :org_id, :firmware_id, :conditions, :is_active]

  def index(%{assigns: %{product: product}} = conn, _params) do
    deployment_groups = ManagedDeployments.get_deployment_groups_by_product(product)
    render(conn, "index.json", deployment_groups: deployment_groups)
  end

  def create(%{assigns: %{org: org, product: product, user: user}} = conn, params) do
    case Map.get(params, "firmware") do
      nil ->
        {:error, :no_firmware_uuid}

      uuid ->
        with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid),
             params <- Map.put(params, "firmware_id", firmware.id),
             params <- Map.put(params, "org_id", org.id),
             params <- whitelist(params, @whitelist_fields),
             {:ok, deployment_group} <- ManagedDeployments.create_deployment_group(params) do
          DeploymentGroupTemplates.audit_deployment_created(user, deployment_group)

          conn
          |> put_status(:created)
          |> put_resp_header(
            "location",
            Routes.api_deployment_group_path(
              conn,
              :show,
              org.name,
              product.name,
              deployment_group.name
            )
          )
          |> render("show.json", deployment_group: %{deployment_group | firmware: firmware})
        end
    end
  end

  def show(%{assigns: %{org: _org, product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name) do
      render(conn, "show.json", deployment_group: deployment_group)
    end
  end

  def update(%{assigns: %{product: product, user: user}} = conn, %{
        "name" => name,
        "deployment" => deployment_group_params
      }) do
    with {:ok, deployment_group} <-
           ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, deployment_group_params} <- update_params(product, deployment_group_params),
         deployment_group_params <- whitelist(deployment_group_params, @whitelist_fields),
         {:ok, %DeploymentGroup{} = updated_deployment_group} <-
           ManagedDeployments.update_deployment_group(
             deployment_group,
             deployment_group_params
           ) do
      DeploymentGroupTemplates.audit_deployment_updated(user, deployment_group)

      render(conn, "show.json", deployment_group: updated_deployment_group)
    end
  end

  def delete(%{assigns: %{product: product}} = conn, %{"name" => name}) do
    with {:ok, deployment_group} <-
           ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, _deployment_group} <- ManagedDeployments.delete_deployment_group(deployment_group) do
      send_resp(conn, :no_content, "")
    end
  end

  defp update_params(product, params) do
    params
    |> maybe_active_from_state()
    |> maybe_firmware_id(product)
    |> case do
      %{} = params -> {:ok, params}
      err -> err
    end
  end

  defp maybe_active_from_state(%{"state" => state} = params) do
    active? = if String.downcase(state) == "on", do: true, else: false
    Map.put(params, "is_active", active?)
  end

  defp maybe_active_from_state(params), do: params

  defp maybe_firmware_id(%{"firmware" => uuid} = params, product) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      Map.put(params, "firmware_id", firmware.id)
    end
  end

  defp maybe_firmware_id(params, _product), do: params
end
