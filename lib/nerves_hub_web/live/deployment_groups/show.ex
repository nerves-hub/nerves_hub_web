defmodule NervesHubWeb.Live.DeploymentGroups.Show do
  use NervesHubWeb, :live_view

  alias LiveFlow.Edge
  alias LiveFlow.Handle
  alias LiveFlow.Node
  alias LiveFlow.State
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
  alias NervesHubWeb.Components.DeploymentGroupPage.WorkflowStepNode
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

  # Ignore events from LiveFlow
  @impl Phoenix.LiveView
  def handle_event("lf:" <> _, _params, socket) do
    {:noreply, socket}
  end

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

  def handle_event("workflow-step-retry", %{"number" => number}, socket) do
    workflow_step_action(socket, :retry, number)
  end

  def handle_event("workflow-step-skip", %{"number" => number}, socket) do
    workflow_step_action(socket, :skip, number)
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

  # The diagram's hook is inside LiveFlow's own live_component and pushes its
  # events there, not here, so measurements reach us through the component's
  # `on_nodes_change` callback rather than a `handle_event`.
  def handle_info({:workflow_nodes_changed, changes}, socket) do
    flow = Enum.reduce(changes, socket.assigns.flow, &apply_node_change(&2, &1))

    socket
    |> assign(:flow, flow)
    |> noreply()
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

  defp workflow_step_action(socket, action, number) do
    authorized!(:"deployment_group:update", socket.assigns.current_scope)

    %{deployment_group: deployment_group} = socket.assigns
    number = String.to_integer(number)

    deployment_group.current_deployment_release_id
    |> Workflows.release_steps()
    |> Enum.find(&(&1.number == number))
    |> case do
      nil ->
        noreply(socket)

      step ->
        socket
        |> apply_step_action(action, step)
        |> assign_workflow(deployment_group)
        |> noreply()
    end
  end

  defp apply_step_action(socket, :skip, step) do
    %{deployment_group: deployment_group, user: user} = socket.assigns

    case Workflows.skip_step(step, user) do
      {:ok, skipped} ->
        AuditLogs.audit!(
          user,
          deployment_group,
          "User #{user.name} skipped workflow step #{skipped.number} (#{DeploymentWorkflowStep.label(skipped)}) for deployment group #{deployment_group.name}"
        )

        # Skipping only clears the way; the orchestrator is what moves the
        # workflow on to the next step.
        :ok = ManagedDeployments.broadcast(deployment_group, "deployments/update")

        put_flash(socket, :info, "Step skipped. Its devices will be picked up by a later step.")

      {:error, :not_skippable} ->
        put_flash(socket, :error, "That step can no longer be skipped.")
    end
  end

  defp apply_step_action(socket, :retry, step) do
    %{deployment_group: deployment_group, user: user} = socket.assigns

    case Workflows.retry_step(deployment_group, step, user) do
      {:ok, retried} ->
        AuditLogs.audit!(
          user,
          deployment_group,
          "User #{user.name} retried workflow step #{retried.number} (#{DeploymentWorkflowStep.label(retried)}) for deployment group #{deployment_group.name}"
        )

        :ok = ManagedDeployments.broadcast(deployment_group, "deployments/update")

        put_flash(socket, :info, "Step restarted. Its devices will be offered the update again.")

      {:error, :not_retryable} ->
        put_flash(socket, :error, "Only a failed step can be retried.")
    end
  end

  # The diagram is built from the steps as they stand, so any change to one is
  # picked up by rebuilding it.
  defp assign_workflow(socket, deployment_group) do
    steps = Workflows.release_steps(deployment_group.current_deployment_release_id)

    socket
    |> assign(:flow, parse_workflow(steps))
    |> assign_awaiting_approval(deployment_group)
  end

  # What the workflow is stopped on, if anything: a step waiting to be approved,
  # or one that failed and is waiting to be retried or skipped.
  defp assign_awaiting_approval(socket, deployment_group) do
    release_id = deployment_group.current_deployment_release_id

    socket
    |> assign(:awaiting_approval, Workflows.awaiting_approval(release_id))
    |> assign(:failed_step, Workflows.failed_step(release_id))
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

  # LiveFlow hangs a handle halfway down a node (`position.y + height / 2`) and
  # positions nodes from their top-left, so nodes of different heights would be
  # joined by sloping arrows. Rather than pad every node out to a common height,
  # each one is placed so that its own middle sits on a shared centre line: a step
  # with no description stays short, and the arrows still run level.
  #
  # Only the browser knows how tall a node ended up, so the heights below are a
  # starting guess and `apply_node_change/2` re-centres each node once it reports
  # what it measured.
  @node_width 230
  @node_gap 60
  @node_centre_y 60

  @estimated_height_with_description 92
  @estimated_height 58

  # `.lf-node-content` pads by 15px either side and `.lf-node` draws a 1px border.
  # The width is pinned so the columns line up; the height is left to the content.
  @node_padding_x 32

  defp create_node(step, total_count) do
    step_data = WorkflowStepNode.node_data(step, @node_width - @node_padding_x)

    height = estimated_height(step)

    node =
      Node.new(
        "step-#{step.number}",
        %{x: (@node_width + @node_gap) * (step.number - 1), y: centre_offset(height)},
        step_data,
        type: :status,
        draggable: "false",
        deletable: false,
        handles: create_handles(step, total_count)
      )

    %{node | width: @node_width, height: height}
  end

  defp estimated_height(%{description: description}) when description in [nil, ""], do: @estimated_height
  defp estimated_height(_step), do: @estimated_height_with_description

  defp centre_offset(nil), do: @node_centre_y
  defp centre_offset(height), do: @node_centre_y - height / 2

  # An edge runs from a source handle to a target handle, so a step needs one of
  # each: the arrow leaves on the right and arrives on the left. Handles are
  # looked up by type, and the first match wins, so making them all sources put
  # every outgoing edge on the node's left-hand side and left every arrowhead
  # with no target to aim at.
  defp create_handles(%{number: 1}, _total_count) do
    [Handle.source(:right, connectable: false)]
  end

  defp create_handles(%{number: num}, total_count) when num == total_count do
    [Handle.target(:left, connectable: false)]
  end

  defp create_handles(_step, _total_count) do
    [Handle.target(:left, connectable: false), Handle.source(:right, connectable: false)]
  end

  defp create_edge(%{number: num}, total_count) when num == total_count, do: nil

  defp create_edge(%{number: num}, _total_count) do
    Edge.new("e#{num}", "step-#{num}", "step-#{num + 1}",
      selectable: false,
      deletable: false,
      marker_end: %{type: :arrow_closed, height: 8, width: 8, stroke_width: 0.5}
    )
  end

  defp node_types(), do: WorkflowStepNode.node_types()

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

  # Re-centre on the measured height. The browser reports a size only when it
  # actually changes, so moving a node in response does not start a loop.
  defp apply_node_change(flow, %{"type" => "dimensions", "id" => id} = change) do
    case Map.get(flow.nodes, id) do
      nil ->
        flow

      node ->
        height = Map.get(change, "height")

        updated = %{
          node
          | width: Map.get(change, "width"),
            height: height,
            measured: true,
            position: %{node.position | y: centre_offset(height)}
        }

        %{flow | nodes: Map.put(flow.nodes, id, updated)}
    end
  end

  defp apply_node_change(flow, %{"type" => "remove", "id" => id}) do
    State.remove_node(flow, id)
  end

  defp apply_node_change(flow, _change), do: flow
end
