defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices
  alias NervesHub.ManagedDeployments

  alias NervesHubWeb.Components.DeploymentGroupPage.Activity, as: ActivityTab
  alias NervesHubWeb.Components.DeploymentGroupPage.ReleaseHistory, as: ReleaseHistoryTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Settings, as: SettingsTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Summary, as: SummaryTab

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{product: product} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, name, true)

    {logs, audit_pager} =
      AuditLogs.logs_for_feed(deployment_group, %{
        page: Map.get(params, "page", 1),
        page_size: 10
      })

    # Use proper links since current pagination links assumes LiveView
    audit_pager =
      audit_pager
      |> Map.from_struct()
      |> Map.put(:links, true)
      |> Map.put(:anchor, "latest-activity")

    inflight_updates = Devices.inflight_updates_for(deployment_group)
    current_device_count = ManagedDeployments.get_device_count(deployment_group)
    updating_count = Devices.updating_count(deployment_group)

    socket
    |> page_title("Deployment Group - #{deployment_group.name} - #{product.name}")
    |> sidebar_tab(:deployments)
    |> selected_tab()
    |> assign(:deployment_group, deployment_group)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, updating_count)
    |> assign(:audit_logs, logs)
    |> assign(:audit_pager, audit_pager)
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:firmware, deployment_group.firmware)
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
    authorized!(:"deployment_group:toggle", socket.assigns.org_user)

    %{deployment_group: deployment_group, user: user} = socket.assigns

    value = !deployment_group.is_active

    {:ok, deployment_group} =
      ManagedDeployments.update_deployment_group(deployment_group, %{is_active: value})

    active_str = if value, do: "active", else: "inactive"
    DeploymentGroupTemplates.audit_deployment_toggle_active(user, deployment_group, active_str)

    socket
    |> put_flash(:info, "Deployment set #{active_str}")
    |> send_toast(:info, "Deployment #{(value && "resumed") || "paused"}")
    |> assign(:deployment_group, deployment_group)
    |> noreply()
  end

  def handle_event("delete", _params, socket) do
    authorized!(:"deployment_group:delete", socket.assigns.org_user)

    %{deployment_group: deployment_group, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = ManagedDeployments.delete_deployment_group(deployment_group)

    DeploymentGroupTemplates.audit_deployment_deleted(user, deployment_group)

    socket
    |> put_flash(:info, "Deployment Group successfully deleted")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/deployment_groups")
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:update_inflight_updates, %{assigns: %{tab: :summary}} = socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)

    %{assigns: %{deployment_group: deployment_group}} = socket

    inflight_updates = Devices.inflight_updates_for(deployment_group)

    send_update(self(), SummaryTab, id: "deployment_group_summary", update_inflight_info: true)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, Devices.updating_count(deployment_group))
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:update_inflight_updates, socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)
    noreply(socket)
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
end
