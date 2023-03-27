defmodule NervesHubWeb.DeploymentLive.Show do
  use NervesHubWeb, :live_view

  require Logger

  alias NervesHub.{Accounts, Deployments, Products, Firmwares}

  def render(assigns) do
    NervesHubWeb.DeploymentView.render("show.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id,
          "deployment_id" => deployment_id,
          "firmware_id" => firmware_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:deployment, fn -> Deployments.get_deployment!(deployment_id) end)
      |> assign_new(:firmware, fn -> Firmwares.get_firmware!(firmware_id) end)
      |> audit_log_assigns(1)

    {:ok, socket}
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      socket_error(socket, live_view_error(exception))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
  end

  def handle_event(
        "delete",
        _val,
        %{assigns: %{org: org, deployment: deployment, product: product, user: user}} = socket
      ) do
    case Deployments.delete_deployment(deployment) do
      {:ok, _} ->
        description = "user #{user.username} deleted deployment #{deployment.name}"

        AuditLogs.audit!(user, deployment, :delete, description, %{
          id: deployment.id,
          name: deployment.name
        })

        socket =
          socket
          |> put_flash(:info, "Deployment deleted")
          |> redirect(to: Routes.deployment_path(socket, :index, org.name, product.name))

        {:noreply, socket}

      {:error, error} ->
        {:noreply,
         put_flash(socket, :error, "Error occurred deleting deployment: #{inspect(error)}")}
    end
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> audit_log_assigns(String.to_integer(page_num))}
  end

  def handle_event(
        "toggle_active",
        %{"isactive" => value},
        %{assigns: %{deployment: deployment, user: user}} = socket
      ) do
    {:ok, updated_deployment} = Deployments.update_deployment(deployment, %{is_active: value})
    active_str = if value, do: "active", else: "inactive"
    description = "user #{user.username} marked deployment #{deployment.name} #{active_str}"
    AuditLogs.audit!(user, deployment, :update, description, %{is_active: value})
    {:noreply, assign(socket, :deployment, updated_deployment)}
  end

  def handle_event(
        "toggle_health_state",
        _params,
        %{assigns: %{deployment: deployment, user: user}} = socket
      ) do
    params = %{healthy: !deployment.healthy}

    socket =
      case Deployments.update_deployment(deployment, params) do
        {:ok, updated_deployment} ->
          AuditLogs.audit!(
            user,
            deployment,
            :update,
            "user #{user.username} updated deployment #{deployment.name}",
            params
          )

          assign(socket, :deployment, updated_deployment)

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to mark health state")
      end

    {:noreply, socket}
  end

  defp audit_log_assigns(%{assigns: %{deployment: deployment}} = socket, page_number) do
    logs = AuditLogs.logs_for_feed(deployment, %{page: page_number, page_size: 10})

    socket
    |> assign(:audit_logs, logs)
    |> assign(:resource_id, deployment.id)
  end
end
