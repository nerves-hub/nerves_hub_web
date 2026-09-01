defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  use NervesHubWeb, :live_view

  alias LiveFlow.Edge
  alias LiveFlow.Handle
  alias LiveFlow.Node
  alias LiveFlow.State
  alias LiveFlow.Validation.Connection
  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.DeploymentGroupTemplates
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.Deployments
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Helpers.Logging
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentWorkflowStep
  alias NervesHub.ManagedDeployments.Workflows
  alias NervesHub.Products
  alias NervesHubWeb.Components.DeploymentGroupPage.Activity, as: ActivityTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Releases, as: ReleasesTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Settings, as: SettingsTab
  alias NervesHubWeb.Components.DeploymentGroupPage.Summary, as: SummaryTab
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    %{"name" => name} = params
    %{current_scope: %{org: org, product: product, user: user}} = socket.assigns

    deployment_group = ManagedDeployments.get_by_product_and_name!(product, name, true)

    Logger.metadata(user_id: user.id, product_id: product.id, deployment_group_id: deployment_group.id)

    if connected?(socket) do
      :ok = Products.PubSub.subscribe(product.id)
      :ok = socket.endpoint.subscribe("deployment:#{deployment_group.id}")
      :ok = socket.endpoint.subscribe("deployment_release:#{deployment_group.current_deployment_release_id}")
    end

    socket
    |> assign(%{org: org, product: product, user: user})
    |> assign(:flow, parse_workflow(deployment_group.current_release.steps))
    |> assign_awaiting_approval(deployment_group)
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
    authorized!(:"deployment_group:toggle", socket.assigns.current_scope)

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

  def handle_event("approve-workflow-step", _params, socket) do
    authorized!(:"deployment_group:update", socket.assigns.current_scope)

    %{deployment_group: deployment_group, user: user, awaiting_approval: step} = socket.assigns

    case step do
      nil ->
        # Somebody else approved it between the page rendering and the click.
        socket |> assign(:awaiting_approval, nil) |> noreply()

      step ->
        step = Workflows.approve_step(step, user)

        AuditLogs.audit!(
          user,
          deployment_group,
          "User #{user.name} approved workflow step #{step.number} (#{step.name}) for deployment group #{deployment_group.name}"
        )

        # Approving only clears the block. The orchestrator is what completes the
        # step and starts the next one, so nudge it rather than leaving the page
        # looking unchanged until its next periodic run.
        :ok = ManagedDeployments.broadcast(deployment_group, "deployments/update")

        socket
        |> assign(:awaiting_approval, nil)
        |> put_flash(:info, "Step approved. The deployment will carry on with the next step.")
        |> noreply()
    end
  end

  def handle_event("delete", _params, socket) do
    authorized!(:"deployment_group:delete", socket.assigns.current_scope)

    %{deployment_group: deployment_group, org: org, product: product, user: user} = socket.assigns

    {:ok, _} = ManagedDeployments.delete_deployment_group(deployment_group)

    DeploymentGroupTemplates.audit_deployment_deleted(user, deployment_group)

    socket
    |> put_flash(:info, "Deployment Group successfully deleted")
    |> push_navigate(to: ~p"/org/#{org}/#{product}/deployment_groups")
    |> noreply()
  end

  def handle_event("move-matched-devices-to-deployment-group", _params, socket) do
    %{assigns: %{current_scope: scope, deployment_group: deployment_group}} = socket

    move_devices = fn ->
      devices = ManagedDeployments.matched_device_ids(deployment_group, in_deployment: false)

      BulkActions.move_many_to_deployment_group(devices, deployment_group, scope.user)
      |> then(fn %{updated: updated_count, ignored: ignored_count} ->
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
        Deployments.remove_unmatched_devices_from_deployment_group(
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

  def handle_event("lf:node_change", %{"changes" => changes}, socket) do
    flow =
      Enum.reduce(changes, socket.assigns.flow, fn change, acc ->
        apply_node_change(acc, change)
      end)

    {:noreply, assign(socket, flow: flow)}
  end

  def handle_event("lf:edge_change", %{"changes" => changes}, socket) do
    flow =
      Enum.reduce(changes, socket.assigns.flow, fn
        %{"type" => "remove", "id" => id}, acc -> State.remove_edge(acc, id)
        _change, acc -> acc
      end)

    {:noreply, assign(socket, flow: flow)}
  end

  def handle_event("lf:connect_end", params, socket) do
    case Connection.validate_and_create(socket.assigns.flow, params) do
      {:ok, edge} ->
        flow = State.add_edge(socket.assigns.flow, edge)
        {:noreply, assign(socket, flow: flow)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("lf:viewport_change", params, socket) do
    flow = State.update_viewport(socket.assigns.flow, params)
    {:noreply, assign(socket, flow: flow)}
  end

  def handle_event("lf:selection_change", %{"nodes" => node_ids, "edges" => edge_ids}, socket) do
    flow =
      socket.assigns.flow
      |> Map.put(:selected_nodes, MapSet.new(node_ids))
      |> Map.put(:selected_edges, MapSet.new(edge_ids))

    nodes =
      Enum.reduce(flow.nodes, %{}, fn {id, node}, acc ->
        Map.put(acc, id, %{node | selected: id in node_ids})
      end)

    edges =
      Enum.reduce(flow.edges, %{}, fn {id, edge}, acc ->
        Map.put(acc, id, %{edge | selected: id in edge_ids})
      end)

    flow = %{flow | nodes: nodes, edges: edges}
    {:noreply, assign(socket, flow: flow)}
  end

  def handle_event("lf:delete_selected", _params, socket) do
    flow = State.delete_selected(socket.assigns.flow)
    {:noreply, assign(socket, flow: flow)}
  end

  # Catch-all for other lf: events (connect_start, connect_move, connect_cancel, etc.)
  def handle_event("lf:" <> _event, _params, socket) do
    {:noreply, socket}
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

    inflight_updates = FirmwareUpdates.inflight_updates_for(deployment_group)

    send_update(SummaryTab, id: "deployment_group_summary", event: :update_inflight_info)

    socket
    |> assign(:inflight_updates, inflight_updates)
    |> assign(:up_to_date_count, Deployments.up_to_date_count(deployment_group))
    |> assign(:waiting_for_update_count, Deployments.waiting_for_update_count(deployment_group))
    |> assign(:updating_count, Deployments.updating_count(deployment_group))
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
    |> follow_release_steps(deployment_group, updated_deployment)
    |> assign(:deployment_group, updated_deployment)
    |> assign(:firmware, updated_deployment.current_release.firmware)
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

  def handle_info(
        %Broadcast{
          topic: "deployment_release:" <> _,
          event: "step/updated",
          payload: %{number: number, status: status}
        },
        socket
      ) do
    socket
    |> assign(:flow, update_step_status(socket.assigns.flow, number, status))
    |> assign_awaiting_approval(socket.assigns.deployment_group)
    |> noreply()
  end

  # Ignore other broadcasts
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  def handle_info({:lf_node_click, _}, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:refresh_device_count, socket) do
    %{assigns: %{deployment_group: deployment_group}} = socket

    updated_deployment =
      ManagedDeployments.get_by_product_and_name!(deployment_group.product, deployment_group.name, true)

    socket
    |> assign(:deployment_group, updated_deployment)
    |> noreply()
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

  # A new release carries its own steps, broadcast on its own topic. Move the
  # subscription across and rebuild the diagram from the new steps.
  defp follow_release_steps(socket, previous, updated) do
    previous_id = previous.current_deployment_release_id
    updated_id = updated.current_deployment_release_id

    if connected?(socket) and previous_id != updated_id do
      :ok = socket.endpoint.unsubscribe("deployment_release:#{previous_id}")
      :ok = socket.endpoint.subscribe("deployment_release:#{updated_id}")
    end

    socket
    |> assign(:flow, parse_workflow(updated.current_release.steps))
    |> assign_awaiting_approval(updated)
  end

  defp assign_awaiting_approval(socket, deployment_group) do
    assign(socket, :awaiting_approval, Workflows.awaiting_approval(deployment_group.current_deployment_release_id))
  end

  # A deployment group with no workflow has no flow to update.
  defp update_step_status(nil, _number, _status), do: nil

  defp update_step_status(flow, number, status) do
    case Map.get(flow.nodes, "step-#{number}") do
      nil ->
        flow

      node ->
        node = %{node | data: %{node.data | status: status}}
        %{flow | nodes: Map.put(flow.nodes, "step-#{number}", node)}
    end
  end

  defp parse_workflow([]), do: nil

  defp parse_workflow(steps) do
    total_count = length(steps)

    nodes = Enum.map(steps, &create_node(&1, total_count))
    edges = Enum.map(steps, &create_edge(&1, total_count)) |> Enum.reject(&is_nil/1)

    State.new(nodes: nodes, edges: edges)
  end

  defp create_node(step, total_count) do
    step_data =
      %{detail: step.description, label: DeploymentWorkflowStep.label(step), status: step.status}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Node.new(
      "step-#{step.number}",
      calculate_positioning(step),
      step_data,
      type: :status,
      draggable: "false",
      deletable: false,
      handles: create_handles(step, total_count)
    )
  end

  defp calculate_positioning(%{number: number, type: type}) do
    y = if(type == :update_devices, do: 1, else: 16)

    %{x: 250 * (number - 1) + 1, y: y}
  end

  defp create_handles(%{number: 1}, _) do
    [Handle.source(:right, connectable: false)]
  end

  defp create_handles(%{number: num}, total_count) when num == total_count do
    [Handle.source(:left, connectable: false)]
  end

  defp create_handles(_step, _total_count) do
    [Handle.source(:left, connectable: false), Handle.source(:right, connectable: false)]
  end

  defp create_edge(%{number: num}, total_count) when num == total_count, do: nil

  defp create_edge(%{number: num}, _total_count) do
    Edge.new("e#{num}", "step-#{num}", "step-#{num + 1}",
      selectable: false,
      deletable: false,
      marker_end: %{type: :arrow_closed, height: 8, width: 8, stroke_width: 0.5}
    )
  end

  defp node_types() do
    %{status: &status_node/1}
  end

  defp status_node(assigns) do
    label = Map.get(assigns.node.data, :label, "Status")
    status = Map.get(assigns.node.data, :status, :waiting)
    detail = Map.get(assigns.node.data, :detail, "")

    {status_color, status_label} =
      case status do
        :waiting -> {"#f59e0b", "Waiting"}
        :in_progress -> {"#615fff", "In Progress"}
        :completed -> {"#22c55e", "Completed"}
        :skipped -> {"#a1a1aa", "Skipped"}
        :error -> {"#ef4444", "Error"}
        _unknown -> {"#a1a1aa", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:status_color, status_color)
      |> assign(:status_label, status_label)
      |> assign(:detail, detail)

    ~H"""
    <div style="min-width: 150px">
      <div style="display: flex; align-items: center; gap: 8px">
        <div style={"width: 10px; height: 10px; border-radius: 50%; background: #{@status_color}; box-shadow: 0 0 6px #{@status_color}80;#{@node.data.status == :in_progress && " animation: pulse 2s infinite;"}"}>
        </div>
        <div>
          <div style="font-weight: 600; font-size: 13px; color: var(--lf-text-primary)">
            {@label}
          </div>
          <div style={"font-size: 11px; font-weight: 500; color: #{@status_color}"}>
            {@status_label}
          </div>
        </div>
      </div>
      <div
        :if={@detail != ""}
        style="font-size: 11px; color: var(--lf-text-muted); margin-top: 6px; padding-top: 6px; border-top: 1px solid var(--lf-border-secondary, #ddd)"
      >
        {@detail}
      </div>
    </div>
    """
  end

  # Private helper for applying node changes
  defp apply_node_change(flow, %{"type" => "position", "id" => id, "position" => pos} = change) do
    case Map.get(flow.nodes, id) do
      nil ->
        flow

      node ->
        updated = %{node | position: %{x: pos["x"] / 1, y: pos["y"] / 1}, dragging: Map.get(change, "dragging", false)}
        %{flow | nodes: Map.put(flow.nodes, id, updated)}
    end
  end

  defp apply_node_change(flow, %{"type" => "dimensions", "id" => id} = change) do
    case Map.get(flow.nodes, id) do
      nil ->
        flow

      node ->
        updated = %{node | width: Map.get(change, "width"), height: Map.get(change, "height"), measured: true}
        %{flow | nodes: Map.put(flow.nodes, id, updated)}
    end
  end

  defp apply_node_change(flow, %{"type" => "remove", "id" => id}) do
    State.remove_node(flow, id)
  end

  defp apply_node_change(flow, _change), do: flow
end
