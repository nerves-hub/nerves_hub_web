defmodule NervesHubWeb.DeploymentController do
  use NervesHubWeb, :controller

  alias NervesHub.Firmwares
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias Ecto.Changeset

  plug(NervesHubWeb.Plugs.FetchDeployment when action in [:show, :toggle_is_active, :delete, :edit, :update])

  def index(%{assigns: %{tenant: %{id: tenant_id}}} = conn, _params) do
    deployments = Deployments.get_deployments_by_tenant(tenant_id)
    render(conn, "index.html", deployments: deployments)
  end

  def new(%{assigns: %{tenant: %{id: tenant_id} = tenant}} = conn, %{
        "deployment" => %{"firmware_id" => firmware_id}
      }) do
    case Firmwares.get_firmware(tenant, firmware_id) do
      {:ok, firmware} ->
        data = %{
          conditions: %{},
          tenant_id: tenant_id,
          firmware_id: firmware.id,
          is_active: false
        }

        changeset =
          %Deployment{}
          |> Deployment.changeset(data)
          |> tags_to_string()

        conn
        |> render(
          "new.html",
          changeset: changeset,
          firmware: firmware,
          firmware_options: []
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: deployment_path(conn, :new))
    end
  end

  def new(%{assigns: %{tenant: %{id: tenant_id}}} = conn, _params) do
    firmwares = Firmwares.get_firmware_by_tenant(tenant_id)

    if Enum.empty?(firmwares) do
      conn
      |> put_flash(:error, "You must upload a firmware version before creating a deployment")
      |> redirect(to: "/firmware")
    else
      conn
      |> render("select-firmware.html", firmwares: firmwares)
    end
  end

  def create(%{assigns: %{tenant: tenant}} = conn, %{"deployment" => params}) do
    tenant
    |> Firmwares.get_firmware(params["firmware_id"])
    |> case do
      {:ok, firmware} ->
        params =
          params
          |> Map.put("tenant_id", tenant.id)
          |> Map.put("is_active", false)
          |> inject_conditions_map()

        result = Deployments.create_deployment(params)

        {firmware, result}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: deployment_path(conn, :new))

      {_, {:ok, _deployment}} ->
        conn
        |> put_flash(:info, "Deployment created")
        |> redirect(to: deployment_path(conn, :index))

      {firmware, {:error, changeset}} ->
        conn
        |> render(
          "new.html",
          changeset: changeset |> tags_to_string(),
          firmware: firmware
        )
    end
  end

  def show(%{assigns: %{deployment: deployment}} = conn, _params) do
    conn
    |> render(
      "show.html",
      deployment: deployment
    )
  end

  def edit(%{assigns: %{tenant: tenant, deployment: deployment}} = conn, _params) do
    tenant
    |> Firmwares.get_firmware(deployment.firmware_id)
    |> case do
      {:ok, firmware} ->
        conn
        |> render(
          "edit.html", deployment: deployment,
                       firmware: firmware,
                       changeset: Deployment.edit_changeset(deployment, %{}) |> tags_to_string()
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: deployment_path(conn, :show, deployment))
    end
  end


  def update(%{assigns: %{tenant: tenant, deployment: deployment}} = conn, %{"deployment" => deployment_params}) do
    params = inject_conditions_map(deployment_params)
    
    tenant
    |> Firmwares.get_firmware(params["firmware_id"])
    |> case do
      {:ok, firmware} ->
        result = Deployments.update_deployment(deployment, params)
        {firmware, result}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: deployment_path(conn, :show, deployment))

      {_, {:ok, deployment}} ->
        conn
        |> put_flash(:info, "Deployment updated")
        |> redirect(to: deployment_path(conn, :show, deployment))

      {firmware, {:error, changeset}} ->
        render(conn, "edit.html", deployment: deployment,
                                  firmware: firmware,
                                  changeset: changeset |> tags_to_string())
    end
  end

  def delete(%{assigns: %{tenant: tenant, deployment: deployment}} = conn, _params) do
    Deployments.delete_deployment(tenant, deployment)

    conn
    |> put_flash(:info, "Deployment successfully deleted")
    |> redirect(to: deployment_path(conn, :index))
  end

  def toggle_is_active(%{assigns: %{deployment: deployment}} = conn, _params) do
    # Runtime error if failure (should never fail)
    {:ok, _} = Deployments.toggle_is_active(deployment)

    conn
    |> redirect(to: deployment_path(conn, :show, deployment.id))
  end

  @doc """
  Convert tags from a list to a comma-separated list (in a string)
  """
  def tags_to_string(%Changeset{} = changeset) do
    conditions =
      changeset
      |> Changeset.get_field(:conditions)

    tags =
      conditions
      |> Map.get("tags", [])
      |> Enum.join(",")

    conditions = Map.put(conditions, "tags", tags)

    changeset
    |> Changeset.put_change(:conditions, conditions)
  end

  defp inject_conditions_map(params) do
    params
    |> Map.put("conditions", %{
      "version" => params["version"],
      "tags" =>
        params["tags"]
        |> tags_as_list()
        |> MapSet.new()
        |> MapSet.to_list()
    })
  end

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
