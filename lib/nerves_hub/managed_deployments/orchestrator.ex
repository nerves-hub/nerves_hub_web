defmodule NervesHub.ManagedDeployments.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestrator will fetch online
  devices in the assigned deployment that need to be updated and send
  pubsub messages to their device channel requesting they be updated.
  """

  use GenServer
  use OpenTelemetryDecorator

  alias NervesHub.DeploymentOrchestratorEvents
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias NervesHub.ManagedDeployments.Orchestrator.DefaultCoordinator
  alias NervesHub.ManagedDeployments.Orchestrator.WorkflowCoordinator
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  require Logger

  @maybe_trigger_interval 3_000

  defmodule State do
    defstruct coordinator: DefaultCoordinator,
              deployment_group: nil,
              rate_limit?: true,
              should_run?: false,
              timer_ref: nil

    @type t ::
            %__MODULE__{
              deployment_group: DeploymentGroup.t(),
              rate_limit?: boolean(),
              timer_ref: reference() | nil,
              should_run?: boolean(),
              coordinator: DefaultCoordinator | WorkflowCoordinator
            }
  end

  def child_spec(deployment_group, rate_limit \\ true) do
    %{
      id: :"distributed_orchestrator_#{deployment_group.id}",
      start: {__MODULE__, :start_link, [deployment_group, rate_limit]},
      restart: :transient
    }
  end

  def start_link(deployment_group, rate_limit) do
    GenServer.start_link(__MODULE__, {deployment_group, rate_limit})
  end

  def start_link(deployment_group) do
    start_link(deployment_group, true)
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.init")
  def init({deployment_group, rate_limit}) do
    :ok = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

    # Join as the consumer for this deployment's orchestrator events. Device-node
    # senders `Group.dispatch` to this key (default cluster), so events reach only
    # this node instead of the whole cluster.
    :ok = DeploymentOrchestratorEvents.subscribe(deployment_group)

    # trigger every two minutes, plus a jitter between 1 and 10 seconds, as a back up
    interval = to_timeout(second: 120 + :rand.uniform(20))
    _ = :timer.send_interval(interval, :trigger_interval)

    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)

    send(self(), :maybe_trigger)

    state = %State{
      deployment_group: deployment_group,
      rate_limit?: rate_limit,
      timer_ref: nil,
      should_run?: true,
      coordinator: select_coordinator(deployment_group)
    }

    {:ok, state}
  end

  def terminate(reason, state) do
    Logger.info("Orchestrator terminated",
      deployment_id: state.deployment_group.id,
      reason: inspect(reason)
    )

    :ok
  end

  @doc """
  Trigger an update for a deployments devices.

  If deployment group's status is `:preparing`, check if deltas are still being
  generated. If so, do nothing. If not, set the status to `:ready` and update devices.

  If deployment group's status is `:ready`, attempt to generated deltas if deployment
  group has them enabled. Then update devices.

  Finds devices matching:

  - the deployment
  - not updating
  - not using the deployment's current firmware
  - currently online

  If there is space for the device based on the concurrent allowed updates
  the device is told to update. This is not guaranteed to be at or under the
  concurrent limit, it's a best effort.

  As devices update and reconnect, the new orchestrator is told that the update
  was successful, and the process is repeated.
  """
  @spec trigger_update(State.t()) :: DeploymentGroup.t()
  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update#noop-inactive")
  def trigger_update(%{deployment_group: %{is_active: false} = deployment_group}), do: deployment_group

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update#status-failed")
  def trigger_update(%{deployment_group: %{status: status} = deployment_group})
      when status in [:preparing, :deltas_failed, :unknown_error] do
    deployment_group
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update")
  def trigger_update(state) do
    :telemetry.execute([:nerves_hub, :deployments, :trigger_update], %{count: 1})

    if state.coordinator.schedule_updates(state.deployment_group) do
      # rerun the deployment check since some devices were skipped
      send(self(), :trigger)
    end

    state.deployment_group
  end

  # if rate limiting isn't enabled, run `trigger_update`
  defp maybe_trigger_update(%State{rate_limit?: false} = state) do
    deployment_group = trigger_update(state)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  # if there is no "delay" timer set, run `trigger_update`
  defp maybe_trigger_update(%State{timer_ref: nil} = state) do
    deployment_group = trigger_update(state)

    timer_ref = Process.send_after(self(), :maybe_trigger, @maybe_trigger_interval)

    {:noreply, %{state | timer_ref: timer_ref, should_run?: false, deployment_group: deployment_group}}
  end

  # if a "delay" timer is set, queue a `trigger_update`
  # since the function above checks for a nil `timer_ref`, we can assume we have one here
  defp maybe_trigger_update(state) do
    {:noreply, %{state | should_run?: true}}
  end

  # if we don't have a `timer_ref` we can run `trigger_update`
  def handle_info(:trigger_interval, %State{timer_ref: nil} = state) do
    deployment_group = trigger_update(state)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  # we can ignore `trigger_interval` since we have a `timer_ref`
  def handle_info(:trigger_interval, state) do
    {:noreply, state}
  end

  # if the 'run again' boolean in the state is `true`, which indicates that indicates
  # that previous call has been skipped, then run `trigger_update` now
  def handle_info(:maybe_trigger, %State{rate_limit?: false} = state) do
    deployment_group = trigger_update(state)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  def handle_info(:maybe_trigger, %State{should_run?: true} = state) do
    deployment_group = trigger_update(state)

    timer_ref = Process.send_after(self(), :maybe_trigger, @maybe_trigger_interval)

    {:noreply, %{state | timer_ref: timer_ref, should_run?: false, deployment_group: deployment_group}}
  end

  # if the 'run again' boolean in the state is `false`, no requests to run the orchestrator
  # again have been received, so we can nil off the timer and move on
  def handle_info(:maybe_trigger, state) do
    {:noreply, %{state | timer_ref: nil}}
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployment/device-online")
  def handle_info(
        %Broadcast{topic: "orchestrator:deployment:" <> _rest, event: "device-online", payload: payload},
        state
      ) do
    if should_trigger?(payload, state.deployment_group) do
      maybe_trigger_update(state)
    else
      {:noreply, state}
    end
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployment/device-added-or-updated")
  def handle_info(%Broadcast{topic: "orchestrator:deployment:" <> _, event: event}, state)
      when event in ["device-added", "device-updated", "bulk-devices-added"] do
    maybe_trigger_update(state)
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{topic: "deployment:" <> _, event: "deployments/update"}, state) do
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(state.deployment_group)

    maybe_trigger_update(%{
      state
      | deployment_group: deployment_group,
        coordinator: select_coordinator(deployment_group)
    })
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployments/update")
  def handle_info(
        %Broadcast{topic: "deployment:" <> _, event: "status/updated", payload: payload},
        %{deployment_group: deployment_group} = state
      ) do
    maybe_trigger_update(%{state | deployment_group: Map.put(deployment_group, :status, payload.to)})
  end

  def handle_info(%Broadcast{topic: "deployment:" <> _, event: "deleted"}, state) do
    {:stop, :normal, state}
  end

  def handle_info(%Broadcast{topic: "orchestrator:deployment:" <> _, event: "deactivated"}, state) do
    {:stop, :normal, state}
  end

  # Catch all for unknown broadcasts on a deployment_group
  def handle_info(%Broadcast{topic: "deployment:" <> _}, state) do
    {:noreply, state}
  end

  def handle_info(:trigger, state) do
    maybe_trigger_update(state)
  end

  def start_orchestrator(%DeploymentGroup{is_active: true} = deployment) do
    if Application.get_env(:nerves_hub, :deploy_env) != "test" do
      ProcessHub.start_child(:deployment_orchestrators, child_spec(deployment))
    end
  end

  def start_orchestrator(_) do
    :ok
  end

  defp should_trigger?(payload, deployment_group) do
    orchestrator_may_push?(payload) and not firmware_match?(payload, deployment_group) and
      not in_penalty_box?(payload)
  end

  # Only :automatic devices are pushed to. A :device_managed device asks for its
  # own updates, and an :off device takes none but a manual push.
  defp orchestrator_may_push?(payload), do: payload.update_mode == :automatic

  defp firmware_match?(payload, deployment_group) do
    payload.firmware_uuid == deployment_group.current_release.firmware.uuid
  end

  defp in_penalty_box?(payload) do
    not is_nil(payload.updates_blocked_until) and
      DateTime.after?(payload.updates_blocked_until, DateTime.utc_now())
  end

  defp select_coordinator(deployment_group) do
    if Enum.any?(deployment_group.current_release.steps) do
      WorkflowCoordinator
    else
      DefaultCoordinator
    end
  end
end
