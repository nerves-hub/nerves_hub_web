defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  alias NervesHubWeb.Components.AuditLogFeed

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
    |> assign_matched_devices_count()
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
    |> put_flash(:info, "Deployment #{(value && "resumed") || "paused"}")
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

  def handle_event("move-matched-devices-to-deployment-group", _params, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    move_devices = fn ->
      deployment_group
      |> ManagedDeployments.matched_device_ids(in_deployment: false)
      |> Devices.move_many_to_deployment_group(deployment_group)
      |> then(fn {:ok, %{updated: updated_count, ignored: ignored_count}} ->
        if ignored_count > 0 do
          {:error, updated_count, ignored_count}
        else
          updated_count
        end
      end)
    end

    socket
    |> start_async(:move_devices_to_deployment, move_devices)
    |> put_flash(:info, "Moving devices to deployment, this may take a moment")
    |> noreply()
  end

  def handle_event("remove-unmatched-devices-from-deployment-group", _params, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    matched_device_ids =
      ManagedDeployments.matched_device_ids(deployment_group, in_deployment: true)

    remove_devices = fn ->
      {:ok, %{updated: updated, ignored: ignored}} =
        Devices.remove_unmatched_devices_from_deployment_group(
          matched_device_ids,
          deployment_group
        )

      if ignored > 0 do
        {:error, updated, ignored}
      else
        updated
      end
    end

    socket
    |> start_async(:remove_devices_from_deployment, remove_devices)
    |> put_flash(:info, "Removing devices from deployment, this may take a moment")
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(
        :move_devices_to_deployment,
        {:ok, {:error, updated_count, ignored_count}},
        socket
      ) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    :ok =
      Logging.log_to_sentry(
        deployment_group,
        "There was an issue moving devices to a deployment group.",
        %{
          updated_count: updated_count,
          ignored_count: ignored_count,
          deployment_group_id: deployment_group.id
        }
      )

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices moved to #{socket.assigns.deployment_group.name}. However, we couldn't move #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> assign_matched_devices_count()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:move_devices_to_deployment, {:ok, devices_updated_count}, socket) do
    socket
    |> put_flash(
      :info,
      "#{devices_updated_count} devices moved to #{socket.assigns.deployment_group.name}"
    )
    |> assign_matched_devices_count()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:move_devices_to_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    socket
    |> put_flash(
      :error,
      "There was an issue moving devices to #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> assign_matched_devices_count()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(
        :remove_devices_from_deployment,
        {:ok, {:error, updated_count, ignored_count}},
        socket
      ) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    :ok =
      Logging.log_to_sentry(
        deployment_group,
        "There was an issue removing devices from a deployment group.",
        %{
          updated_count: updated_count,
          ignored_count: ignored_count,
          deployment_group_id: deployment_group.id
        }
      )

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices removed from #{socket.assigns.deployment_group.name}. However, we couldn't remove #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> assign_matched_devices_count()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:remove_devices_from_deployment, {:ok, devices_removed_count}, socket) do
    socket
    |> put_flash(
      :info,
      "#{devices_removed_count} devices removed from #{socket.assigns.deployment_group.name}"
    )
    |> assign_matched_devices_count()
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:remove_devices_from_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    socket
    |> put_flash(
      :error,
      "There was an issue removing devices from #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> assign_matched_devices_count()
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

  defp deployment_group_percentage(%{total_updating_devices: 0}), do: 100

  defp deployment_group_percentage(deployment_group) do
    floor(
      deployment_group.current_updated_devices / deployment_group.total_updating_devices * 100
    )
  end

  defp help_message_for(field) do
    case field do
      :failure_threshold ->
        "Maximum number of target devices from this deployment group that can be in an unhealthy state before marking the deployment group unhealthy"

      :failure_rate ->
        "Maximum number of device install failures from this deployment group within X seconds before being marked unhealthy"

      :device_failure_rate ->
        "Maximum number of device failures within X seconds a device can have for this deployment group before being marked unhealthy"

      :device_failure_threshold ->
        "Maximum number of install attempts and/or failures a device can have for this deployment group before being marked unhealthy"

      :penalty_timeout_minutes ->
        "Number of minutes a device is placed in the penalty box for reaching the failure rate and threshold"
    end
  end

  defp version(%DeploymentGroup{conditions: %{"version" => ""}}), do: "-"
  defp version(%DeploymentGroup{conditions: %{"version" => version}}), do: version

  defp firmware_summary(%Firmware{version: nil}) do
    ["Unknown"]
  end

  defp firmware_summary(%Firmware{} = f) do
    ["#{firmware_display_name(f)}"]
  end

  defp firmware_summary(%DeploymentGroup{firmware: %Firmware{} = f}) do
    firmware_summary(f)
  end

  defp firmware_summary(
         %DeploymentGroup{firmware: %Ecto.Association.NotLoaded{}} = deployment_group
       ) do
    ManagedDeployments.preload_firmware_and_archive(deployment_group)
  end

  defp tags(%DeploymentGroup{conditions: %{"tags" => tags}}), do: tags

  defp opposite_status(%DeploymentGroup{is_active: true}), do: "Off"
  defp opposite_status(%DeploymentGroup{is_active: false}), do: "On"

  defp firmware_display_name(%Firmware{} = f) do
    "#{f.version} #{f.platform} #{f.architecture} #{f.uuid}"
  end

  defp assign_matched_devices_count(%{assigns: %{deployment_group: deployment_group}} = socket) do
    current_device_count = ManagedDeployments.get_device_count(deployment_group)

    matched_devices_count =
      ManagedDeployments.matched_devices_count(deployment_group, in_deployment: true)

    matched_devices_outside_deployment_group_count =
      ManagedDeployments.matched_devices_count(deployment_group, in_deployment: false)

    socket
    |> assign(:matched_device_count, matched_devices_count)
    |> assign(:unmatched_device_count, current_device_count - matched_devices_count)
    |> assign(
      :matched_devices_outside_deployment_group_count,
      matched_devices_outside_deployment_group_count
    )
    |> assign(:deployment_group, %{deployment_group | device_count: current_device_count})
  end
end
