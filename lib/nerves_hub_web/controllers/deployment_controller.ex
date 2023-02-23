defmodule NervesHubWeb.DeploymentController do
  use NervesHubWeb, :controller

  alias NervesHub.AuditLogs
  alias NervesHub.Firmwares
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias Ecto.Changeset

  plug(:validate_role, [product: :delete] when action in [:delete])
  plug(:validate_role, [product: :write] when action in [:new, :create, :edit, :update])
  plug(:validate_role, [product: :read] when action in [:index, :show, :export_audit_logs])

  def index(%{assigns: %{org: _org, product: %{id: product_id}}} = conn, _params) do
    deployments = Deployments.get_deployments_by_product(product_id)
    render(conn, "index.html", deployments: deployments)
  end

  def new(%{assigns: %{org: org, product: product}} = conn, %{
        "deployment" => %{"firmware_id" => firmware_id}
      }) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)

    case Firmwares.get_firmware(org, firmware_id) do
      {:ok, firmware} ->
        data = %{
          conditions: %{},
          org_id: org.id,
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
          firmwares: firmwares,
          firmware_options: []
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: Routes.deployment_path(conn, :new, org.name, product.name))
    end
  end

  def new(%{assigns: %{org: org, product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)

    if Enum.empty?(firmwares) do
      conn
      |> put_flash(:error, "You must upload a firmware version before creating a deployment")
      |> redirect(to: Routes.firmware_path(conn, :upload, org.name, product.name))
    else
      conn
      |> render("new.html", firmwares: firmwares, changeset: %Changeset{data: %Deployment{}})
    end
  end

  def create(%{assigns: %{org: org, product: product, user: user}} = conn, %{
        "deployment" => params
      }) do
    params =
      params
      |> inject_conditions_map()
      |> whitelist([:name, :conditions, :firmware_id])
      |> Map.put(:org_id, org.id)
      |> Map.put(:is_active, false)

    firmwares = Firmwares.get_firmwares_by_product(product.id)

    org
    |> Firmwares.get_firmware(params[:firmware_id])
    |> case do
      {:ok, firmware} ->
        {firmware, Deployments.create_deployment(params)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
    |> case do
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid firmware selected")
        |> redirect(to: Routes.deployment_path(conn, :new, org.name, product.name))

      {_, {:ok, deployment}} ->
        AuditLogs.audit!(
          user,
          deployment,
          :create,
          "user #{user.username} created deployment #{deployment.name}",
          params
        )

        conn
        |> put_flash(:info, "Deployment created")
        |> redirect(to: Routes.deployment_path(conn, :index, org.name, product.name))

      {firmware, {:error, changeset}} ->
        conn
        |> render(
          "new.html",
          changeset: changeset |> tags_to_string(),
          firmware: firmware,
          firmwares: firmwares
        )
    end
  end

  def show(
        %{assigns: %{user: user, org: org, product: product, deployment: deployment}} = conn,
        _params
      ) do
    conn
    |> live_render(
      NervesHubWeb.DeploymentLive.Show,
      session: %{
        "auth_user_id" => user.id,
        "org_id" => org.id,
        "product_id" => product.id,
        "deployment_id" => deployment.id,
        "firmware_id" => deployment.firmware_id
      }
    )
  end

  def edit(%{assigns: %{deployment: deployment, product: product}} = conn, _params) do
    firmwares = Firmwares.get_firmwares_by_product(product.id)

    conn
    |> render(
      "edit.html",
      deployment: deployment,
      firmware: deployment.firmware,
      firmwares: firmwares,
      changeset:
        Deployment.changeset(deployment, %{})
        |> tags_to_string()
    )
  end

  def update(
        %{assigns: %{org: org, product: product, user: user, deployment: deployment}} = conn,
        %{"deployment" => deployment_params}
      ) do
    allowed_fields = [
      :conditions,
      :device_failure_rate_amount,
      :device_failure_rate_seconds,
      :device_failure_threshold,
      :failure_rate_amount,
      :failure_rate_seconds,
      :failure_threshold,
      :firmware_id,
      :name,
      :is_active
    ]

    params =
      deployment_params
      |> inject_conditions_map()
      |> whitelist(allowed_fields)

    Deployments.update_deployment(deployment, params)
    |> case do
      {:ok, updated} ->
        # Use original deployment so changes will get
        # marked in audit log
        AuditLogs.audit!(
          user,
          deployment,
          :update,
          "user #{user.username} updated deployment #{deployment.name}",
          params
        )

        conn
        |> put_flash(:info, "Deployment updated")
        |> redirect(
          to:
            Routes.deployment_path(
              conn,
              :show,
              org.name,
              product.name,
              updated.name
            )
        )

      {:error, changeset} ->
        render(
          conn,
          "edit.html",
          deployment: deployment,
          firmware: deployment.firmware,
          firmwares: Firmwares.get_firmwares_by_product(product.id),
          changeset: changeset |> tags_to_string()
        )
    end
  end

  def delete(%{assigns: %{org: org, product: product, deployment: deployment}} = conn, _params) do
    Deployments.delete_deployment(deployment)

    conn
    |> put_flash(:info, "Deployment successfully deleted")
    |> redirect(to: Routes.deployment_path(conn, :index, org.name, product.name))
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

  def export_audit_logs(
        %{assigns: %{org: org, product: product, deployment: deployment}} = conn,
        _params
      ) do
    conn =
      case AuditLogs.logs_for(deployment) do
        [] ->
          put_flash(conn, :error, "No audit logs exist for this deployment.")
          |> redirect(to: Routes.deployment_path(conn, :index, org.name, product.name))

        audit_logs ->
          audit_logs = AuditLogs.format_for_csv(audit_logs)

          conn
          |> send_download({:binary, audit_logs}, filename: "#{deployment.name}-audit-logs.csv")
      end

    {:noreply, conn}
  end
end
