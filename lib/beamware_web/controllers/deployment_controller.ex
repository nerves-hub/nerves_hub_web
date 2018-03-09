defmodule BeamwareWeb.DeploymentController do
  use BeamwareWeb, :controller

  alias Beamware.Firmwares
  alias Beamware.Deployments
  alias Beamware.Deployments.Deployment
  alias Ecto.Changeset

  plug(BeamwareWeb.Plugs.FetchDeployment when action in [:show, :toggle_is_active])

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
          |> Map.put("conditions", %{
            "version" => params["version"],
            "tags" =>
              params["tags"]
              |> tags_as_list()
              |> MapSet.new()
              |> MapSet.to_list()
          })

        result = Deployments.create_deployment(tenant, params)

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

  def tags_as_list(""), do: []

  def tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
