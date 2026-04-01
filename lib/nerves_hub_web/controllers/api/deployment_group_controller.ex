defmodule NervesHubWeb.API.DeploymentGroupController do
  use NervesHubWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias NervesHub.Archives
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHubWeb.API.Schemas.DeploymentGroupSchemas

  security([%{}, %{"bearer_auth" => []}])
  tags(["Deployment Groups"])

  plug(:validate_role, [org: :manage] when action in [:create, :update, :delete])
  plug(:validate_role, [org: :view] when action in [:index, :show])

  operation(:index,
    summary: "List all Deployment Groups for a Product",
    responses: [
      ok: {"Deployment Group list response", "application/json", DeploymentGroupSchemas.DeploymentGroupListResponse}
    ]
  )

  def index(%{assigns: %{current_scope: %{product: product}}} = conn, _params) do
    deployment_groups = ManagedDeployments.get_deployment_groups_by_product(product)
    render(conn, :index, deployment_groups: deployment_groups)
  end

  operation(:create, summary: "Create a new Deployment Group for a Product")

  def create(%{assigns: %{current_scope: %{org: org, product: product, user: user}}} = conn, params) do
    firmware = Firmwares.get_by_uuid(product, Map.get(params, "firmware"))

    with {:ok, deployment_group} <- ManagedDeployments.create_deployment_group(params, product, firmware, user) do
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
      |> render(:show, deployment_group: deployment_group)
    end
  end

  operation(:show,
    summary: "Show a Deployment Group",
    responses: [
      ok: {"Deployment Group response", "application/json", DeploymentGroupSchemas.DeploymentGroupResponse}
    ]
  )

  def show(%{assigns: %{current_scope: %{product: product}}} = conn, %{"name" => name}) do
    with {:ok, deployment_group} <- ManagedDeployments.get_deployment_group_by_name(product, name) do
      render(conn, :show, deployment_group: deployment_group)
    end
  end

  operation(:update, summary: "Update a Deployment Group")

  def update(%{assigns: %{current_scope: %{product: product, user: user}}} = conn, %{
        "name" => name,
        "deployment" => deployment_group_params
      })
      when is_map_key(deployment_group_params, "firmware_id") or is_map_key(deployment_group_params, "archive_id") do
    firmware = Firmwares.get_by_id(product, deployment_group_params["firmware_id"])
    archive = Archives.get_by_id(product, deployment_group_params["archive_id"])

    with {:ok, deployment_group} <-
           ManagedDeployments.get_deployment_group_by_name(product, name),
         {:ok, {_deployment_release, updated_deployment_group}} <-
           ManagedDeployments.create_deployment_release(
             deployment_group,
             firmware,
             archive,
             user,
             deployment_group_params
           ) do
      DeploymentGroupTemplates.audit_new_deployment_release(user, deployment_group)

      render(conn, :show, deployment_group: updated_deployment_group)
    end
  end

  def update(%{assigns: %{current_scope: %{product: product, user: user}}} = conn, %{
        "name" => name,
        "deployment" => deployment_group_params
      }) do
    with {:ok, deployment_group} <-
           ManagedDeployments.get_deployment_group_by_name(product, name),
         params = update_params(product, deployment_group_params),
         {:ok, updated_deployment_group} <-
           ManagedDeployments.update_deployment_group(deployment_group, params, user) do
      DeploymentGroupTemplates.audit_deployment_updated(user, deployment_group)

      render(conn, :show, deployment_group: updated_deployment_group)
    end
  end

  operation(:delete, summary: "Delete a Product's Deployment Group")

  def delete(%{assigns: %{current_scope: %{product: product}}} = conn, %{"name" => name}) do
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
  end

  defp maybe_active_from_state(%{"state" => state} = params) do
    active? = if String.downcase(state) == "on", do: true, else: false
    Map.put(params, "is_active", active?)
  end

  defp maybe_active_from_state(params), do: params

  defp maybe_firmware_id(%{"firmware" => uuid} = params, product) do
    case Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:ok, firmware} ->
        Map.put(params, "firmware_id", firmware.id)

      _ ->
        params
    end
  end

  defp maybe_firmware_id(params, _product), do: params
end
