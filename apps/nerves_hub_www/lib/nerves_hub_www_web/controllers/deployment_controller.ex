defmodule NervesHubWWWWeb.DeploymentController do
  use NervesHubWWWWeb, :controller

  alias NervesHubCore.Firmwares
  alias NervesHubCore.Deployments
  alias NervesHubCore.Deployments.Deployment
  alias Ecto.Changeset

  def index(%{assigns: %{tenant: _tenant, product: %{id: product_id}}} = conn, _params) do
    deployments = Deployments.get_deployments_by_product(product_id)
    render(conn, "index.html", deployments: deployments)
  end

  def new(%{assigns: %{tenant: tenant, product: product}} = conn, %{
        "deployment" => %{"firmware_id" => firmware_id}
      }) do
    case Firmwares.get_firmware(tenant, firmware_id) do
      {:ok, firmware} ->
        data = %{
          conditions: %{},
          tenant_id: tenant.id,
          product_id: product.id,
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
        |> redirect(to: product_deployment_path(conn, :new, product.id))
    end
  end

  def new(%{assigns: %{tenant: _tenant, product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)

    if Enum.empty?(firmwares) do
      conn
      |> put_flash(:error, "You must upload a firmware version before creating a deployment")
      |> redirect(to: product_firmware_path(conn, :upload, product.id))
    else
      conn
      |> render("select-firmware.html", firmwares: firmwares)
    end
  end

  def create(%{assigns: %{tenant: tenant, product: product}} = conn, %{"deployment" => params}) do
    tenant
    |> Firmwares.get_firmware(params["firmware_id"])
    |> case do
      {:ok, firmware} ->
        params =
          params
          |> Map.put("tenant_id", tenant.id)
          |> Map.put("product_id", product.id)
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
        |> redirect(to: product_deployment_path(conn, :new, product.id))

      {_, {:ok, _deployment}} ->
        conn
        |> put_flash(:info, "Deployment created")
        |> redirect(to: product_deployment_path(conn, :index, product.id))

      {firmware, {:error, changeset}} ->
        conn
        |> render(
          "new.html",
          changeset: changeset |> tags_to_string(),
          firmware: firmware
        )
    end
  end

  def show(%{assigns: %{tenant: _tenant, product: product}} = conn, %{"id" => deployment_id}) do
    {:ok, deployment} = Deployments.get_deployment(product, deployment_id)

    conn
    |> render(
      "show.html",
      deployment: deployment
    )
  end

  def edit(%{assigns: %{tenant: _tenant, product: product}} = conn, %{"id" => deployment_id}) do
    {:ok, deployment} = Deployments.get_deployment(product, deployment_id)

    conn
    |> render(
      "edit.html",
      deployment: deployment,
      firmware: deployment.firmware,
      changeset:
        Deployment.changeset(deployment, %{})
        |> tags_to_string()
    )
  end

  def update(
        %{assigns: %{product: product}} = conn,
        %{"id" => deployment_id, "deployment" => deployment_params}
      ) do
    params = inject_conditions_map(deployment_params)

    {:ok, deployment} = Deployments.get_deployment(product, deployment_id)

    Deployments.update_deployment(deployment, params)
    |> case do
      {:ok, deployment} ->
        conn
        |> put_flash(:info, "Deployment updated")
        |> redirect(to: product_deployment_path(conn, :show, product.id, deployment))

      {:error, changeset} ->
        render(
          conn,
          "edit.html",
          deployment: deployment,
          firmware: deployment.firmware,
          changeset: changeset |> tags_to_string()
        )
    end
  end

  def delete(%{assigns: %{tenant: _tenant, product: product}} = conn, %{"id" => id}) do
    {:ok, deployment} = product |> Deployments.get_deployment(id)

    Deployments.delete_deployment(deployment)

    conn
    |> put_flash(:info, "Deployment successfully deleted")
    |> redirect(to: product_deployment_path(conn, :index, product.id))
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

  defp inject_conditions_map(%{"version" => version, "tags" => tags} = params) do
    params
    |> Map.put("conditions", %{
      "version" => version,
      "tags" =>
        tags
        |> tags_as_list()
        |> MapSet.new()
        |> MapSet.to_list()
    })
  end

  defp inject_conditions_map(params), do: params

  defp tags_as_list(""), do: []

  defp tags_as_list(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
