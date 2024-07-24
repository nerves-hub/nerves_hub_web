defmodule NervesHubWeb.Live.Deployments.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Repo

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{product: product} = socket.assigns

    deployment = Deployments.get_by_product_and_name!(product, name)

    logs =
      AuditLogs.logs_for_feed(deployment, %{
        page: Map.get(params, "page", 1),
        page_size: 10
      })

    # Use proper links since current pagination links assumes LiveView
    logs =
      logs
      |> Map.put(:links, true)
      |> Map.put(:anchor, "latest-activity")

    inflight_updates = Devices.inflight_updates_for(deployment)

    socket
    |> page_title("Deployment - #{deployment.name} - #{product.name}")
    |> assign(:deployment, deployment)
    |> assign(:audit_logs, logs)
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:firmware, deployment.firmware)
    |> schedule_inflight_updates_updater()
    |> ok()
  end

  defp schedule_inflight_updates_updater(socket) do
    if connected?(socket) do
      Process.send_after(self(), :update_inflight_updates, 5000)
      socket
    else
      socket
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle", _params, socket) do
    authorized!(:"deployment:toggle", socket.assigns.org_user)

    %{deployment: deployment, user: user} = socket.assigns

    value = !deployment.is_active
    {:ok, deployment} = Deployments.update_deployment(deployment, %{is_active: value})

    active_str = if value, do: "active", else: "inactive"
    description = "#{user.name} marked deployment #{deployment.name} #{active_str}"
    AuditLogs.audit!(user, deployment, description)

    socket
    |> put_flash(:info, "Deployment set #{active_str}")
    |> assign(:deployment, deployment)
    |> noreply()
  end

  def handle_event("delete", _params, socket) do
    authorized!(:"deployment:delete", socket.assigns.org_user)

    %{deployment: deployment, org: org, product: product, user: user} = socket.assigns

    description = "#{user.name} deleted deployment #{deployment.name}"

    AuditLogs.audit!(user, deployment, description)

    {:ok, _} = Deployments.delete_deployment(deployment)

    socket
    |> put_flash(:info, "Deployment successfully deleted")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployments")
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:update_inflight_updates, socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)

    inflight_updates = Devices.inflight_updates_for(socket.assigns.deployment)

    {:noreply, assign(socket, :inflight_updates, inflight_updates)}
  end

  defp deployment_percentage(%{total_updating_devices: 0}), do: 100

  defp deployment_percentage(deployment) do
    floor(deployment.current_updated_devices / deployment.total_updating_devices * 100)
  end

  defp help_message_for(field) do
    case field do
      :failure_threshold ->
        "Maximum number of target devices from this deployment that can be in an unhealthy state before marking the deployment unhealthy"

      :failure_rate ->
        "Maximum number of device install failures from this deployment within X seconds before being marked unhealthy"

      :device_failure_rate ->
        "Maximum number of device failures within X seconds a device can have for this deployment before being marked unhealthy"

      :device_failure_threshold ->
        "Maximum number of install attempts and/or failures a device can have for this deployment before being marked unhealthy"

      :penalty_timeout_minutes ->
        "Number of minutes a device is placed in the penalty box for reaching the failure rate and threshold"
    end
  end

  defp version(%Deployment{conditions: %{"version" => ""}}), do: "-"
  defp version(%Deployment{conditions: %{"version" => version}}), do: version

  defp firmware_summary(%Firmware{version: nil}) do
    ["Unknown"]
  end

  defp firmware_summary(%Firmware{} = f) do
    ["#{firmware_display_name(f)}"]
  end

  defp firmware_summary(%Deployment{firmware: %Firmware{} = f}) do
    firmware_summary(f)
  end

  defp firmware_summary(%Deployment{firmware: %Ecto.Association.NotLoaded{}} = deployment) do
    Repo.preload(deployment, [:firmware])
    |> firmware_summary()
  end

  defp tags(%Deployment{conditions: %{"tags" => tags}}), do: tags

  defp opposite_status(%Deployment{is_active: true}), do: "Off"
  defp opposite_status(%Deployment{is_active: false}), do: "On"

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
  end
end
