defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHubWeb.Components.DeploymentGroupPage.Activity, as: ActivityTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Releases, as: ReleasesTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Settings, as: SettingsTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Summary, as: SummaryTab
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{product: product, user: user} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, name, true)

    Logger.metadata(user_id: user.id, product_id: product.id, deployment_group_id: deployment_group.id)

    if connected?(socket) do
      :ok = socket.endpoint.subscribe("product:#{product.id}")
      :ok = socket.endpoint.subscribe("deployment:#{deployment_group.id}")
    end

    socket
    |> page_title("Deployment Group - #{deployment_group.name} - #{product.name}")
    |> sidebar_tab(:deployments)
    |> selected_tab()
    |> assign(:deployment_group, deployment_group)
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
      ManagedDeployments.update_deployment_group(deployment_group, %{is_active: value}, user)

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
    |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups")
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
  def handle_async(:move_devices_to_deployment, {:ok, {:error, updated_count, ignored_count}}, socket) do
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

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices moved to #{socket.assigns.deployment_group.name}. However, we couldn't move #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:move_devices_to_deployment, {:ok, devices_updated_count}, socket) do
    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :info,
      "#{devices_updated_count} devices moved to #{socket.assigns.deployment_group.name}"
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:move_devices_to_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :error,
      "There was an issue moving devices to #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:remove_devices_from_deployment, {:ok, {:error, updated_count, ignored_count}}, socket) do
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

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :error,
      "#{updated_count} devices removed from #{socket.assigns.deployment_group.name}. However, we couldn't remove #{ignored_count} devices. We've been notified and are looking into it."
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:remove_devices_from_deployment, {:ok, devices_removed_count}, socket) do
    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :info,
      "#{devices_removed_count} devices removed from #{socket.assigns.deployment_group.name}"
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_async(:remove_devices_from_deployment, {:exit, reason}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket
    :ok = Logging.log_to_sentry(deployment_group, reason)

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_matched_devices_count)

    socket
    |> put_flash(
      :error,
      "There was an issue removing devices from #{deployment_group.name}. We've been notified and are looking into it."
    )
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:update_inflight_updates, %{assigns: %{tab: :summary}} = socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)

    %{assigns: %{deployment_group: deployment_group}} = socket

    inflight_updates = Devices.inflight_updates_for(deployment_group)

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_inflight_info)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Devices.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Devices.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, Devices.updating_count(deployment_group))
    |> noreply()
  end

  def handle_info(:update_inflight_updates, socket) do
    Process.send_after(self(), :update_inflight_updates, 5000)
    noreply(socket)
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    updated_deployment =
      ManagedDeployments.get_by_product_and_name!(deployment_group.product, deployment_group.name, true)

    send_update(SummaryTab, id: "deployment_group_summary", updated_deployment: updated_deployment)

    socket
    |> assign(:deployment_group, updated_deployment)
    |> assign(:firmware, updated_deployment.firmware)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "status/updated"}, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    updated_deployment =
      ManagedDeployments.get_by_product_and_name!(deployment_group.product, deployment_group.name, true)

    send_update(SummaryTab, id: "deployment_group_summary", updated_deployment: updated_deployment)

    socket
    |> assign(:deployment_group, updated_deployment)
    |> noreply()
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/created", payload: %{firmware: firmware}},
        socket
      ) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: {:firmware_created, firmware})

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{topic: "product:" <> _product_id, event: "firmware/deleted", payload: %{firmware: firmware}},
        socket
      ) do
    send_update(ReleasesTab, id: "deployment_group_releases", event: {:firmware_deleted, firmware})

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "stat:logged"}, socket) do
    send_update(SummaryTab, id: "deployment_group_summary", event: :stat_logged)

    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: "firmware:" <> _, event: "delta/status_update"}, socket) do
    send_update(SummaryTab, id: "deployment_group_summary", event: :firmware_deltas_updated)
    {:noreply, socket}
  end

  # Ignore other broadcasts
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:flash, level, message}, socket) do
    socket
    |> put_flash(level, message)
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
end
