defmodule NervesHubWeb.Live.Deployments.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentTemplates
  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices
  alias NervesHub.Firmwares.Firmware

  alias NervesHubWeb.Components.AuditLogFeed

  alias NervesHubWeb.Components.DeploymentPage.Summary, as: SummaryTab
  alias NervesHubWeb.Components.DeploymentPage.Activity, as: ActivityTab
  alias NervesHubWeb.Components.DeploymentPage.ReleaseHistory, as: ReleaseHistoryTab
  alias NervesHubWeb.Components.DeploymentPage.Settings, as: SettingsTab

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{product: product} = socket.assigns

    deployment = Deployments.get_by_product_and_name!(product, name, true)

    {logs, audit_pager} =
      AuditLogs.logs_for_feed(deployment, %{
        page: Map.get(params, "page", 1),
        page_size: 10
      })

    # Use proper links since current pagination links assumes LiveView
    audit_pager =
      audit_pager
      |> Map.from_struct()
      |> Map.put(:links, true)
      |> Map.put(:anchor, "latest-activity")

    inflight_updates = Devices.inflight_updates_for(deployment)
    current_device_count = Deployments.get_device_count(deployment)

    socket
    |> page_title("Deployment - #{deployment.name} - #{product.name}")
    |> sidebar_tab(:deployments)
    |> selected_tab()
    |> assign(:deployment, deployment)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment))
    |> assign(:audit_logs, logs)
    |> assign(:audit_pager, audit_pager)
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:firmware, deployment.firmware)
    |> assign(:current_device_count, current_device_count)
    |> schedule_inflight_updates_updater()
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_params(_params, _uri, socket) do
    socket
    |> selected_tab()
    |> noreply()
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
    DeploymentTemplates.audit_deployment_toggle_active(user, deployment, active_str)

    socket
    |> put_flash(:info, "Deployment set #{active_str}")
    |> send_toast(:info, "Deployment #{(value && "resumed") || "paused"}")
    |> assign(:deployment, deployment)
    |> noreply()
  end

  def handle_event("delete", _params, socket) do
    authorized!(:"deployment:delete", socket.assigns.org_user)

    %{deployment: deployment, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = Deployments.delete_deployment(deployment)

    DeploymentTemplates.audit_deployment_deleted(user, deployment)

    socket
    |> put_flash(:info, "Deployment successfully deleted")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployments")
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:update_inflight_updates, socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)

    %{assigns: %{deployment: deployment}} = socket

    inflight_updates = Devices.inflight_updates_for(deployment)

    send_update(self(), SummaryTab, id: "deployment_summary", update_inflight_info: true)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment))
    |> noreply()
  end

  defp selected_tab(socket) do
    assign(socket, :tab, socket.assigns.live_action || :details)
  end

  # TODO: refactor to use tailwind attributes
  defp tab_classes(tab_selected, tab) do
    if tab_selected == tab do
      "px-6 py-2 h-11 font-normal text-sm text-neutral-50 border-b border-indigo-500 bg-tab-selected relative -bottom-px"
    else
      "px-6 py-2 h-11 font-normal text-sm text-zinc-300 hover:border-b hover:border-indigo-500 relative -bottom-px"
    end
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
    Deployments.preload_firmware_and_archive(deployment)
    |> firmware_summary()
  end

  defp tags(%Deployment{conditions: %{"tags" => tags}}), do: tags

  defp opposite_status(%Deployment{is_active: true}), do: "Off"
  defp opposite_status(%Deployment{is_active: false}), do: "On"

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
  end
end
