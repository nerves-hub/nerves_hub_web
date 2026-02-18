defmodule NervesHub.ManagedDeployments.Distributed.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestrator will fetch online
  devices in the assigned deployment that need to be updated and send
  pubsub messages to their device channel requesting they be updated.
  """

  use GenServer
  use OpenTelemetryDecorator

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  require Logger

  @maybe_trigger_interval 3_000

  defmodule State do
    defstruct deployment_group: nil,
              rate_limit?: true,
              should_run?: false,
              timer_ref: nil

    @type t ::
            %__MODULE__{
              deployment_group: DeploymentGroup.t(),
              rate_limit?: boolean(),
              timer_ref: reference() | nil,
              should_run?: boolean()
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

    :ok =
      PubSub.subscribe(NervesHub.PubSub, "orchestrator:deployment:#{deployment_group.id}")

    # trigger every two minutes, plus a jitter between 1 and 10 seconds, as a back up
    interval = to_timeout(second: 120 + :rand.uniform(20))
    _ = :timer.send_interval(interval, :trigger_interval)

    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(deployment_group)

    send(self(), :maybe_trigger)

    state = %State{
      deployment_group: deployment_group,
      rate_limit?: rate_limit,
      timer_ref: nil,
      should_run?: true
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
  @spec trigger_update(DeploymentGroup.t()) :: DeploymentGroup.t()
  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update#noop-inactive")
  def trigger_update(%DeploymentGroup{is_active: false} = deployment_group), do: deployment_group

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update#status-failed")
  def trigger_update(%DeploymentGroup{status: status} = deployment_group)
      when status in [:preparing, :deltas_failed, :unknown_error] do
    deployment_group
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.trigger_update")
  def trigger_update(deployment_group) do
    do_trigger_update(deployment_group)

    deployment_group
  end

  defp do_trigger_update(deployment_group) do
    :telemetry.execute([:nerves_hub, :deployments, :trigger_update], %{count: 1})

    # Process priority queue first, if enabled
    skipped_priority_updates = maybe_do_priority_update(deployment_group)

    # Process normal queue
    slots = available_slots(deployment_group)

    if slots > 0 do
      available = Devices.available_for_update(deployment_group, slots)
      updated_count = schedule_devices!(available, deployment_group, false)

      if length(available) != updated_count or skipped_priority_updates > 0 do
        # rerun the deployment check since some devices were skipped
        send(self(), :trigger)
      end
    end
  end

  # Process priority queue updates for devices below the firmware version threshold.
  # Returns the number of devices that were skipped (not updated).
  @spec maybe_do_priority_update(DeploymentGroup.t()) :: non_neg_integer()

  defp maybe_do_priority_update(%DeploymentGroup{priority_queue_enabled: false}), do: 0

  defp maybe_do_priority_update(deployment_group) do
    priority_slots = available_priority_slots(deployment_group)

    if priority_slots > 0 do
      available = Devices.available_for_priority_update(deployment_group, priority_slots)

      length(available) - schedule_devices!(available, deployment_group, true)
    else
      0
    end
  end

  @doc """
  Determine how many devices should update in the priority queue based on
  the priority queue update limit and the number currently updating in priority queue.
  """
  @spec available_priority_slots(DeploymentGroup.t()) :: non_neg_integer()
  def available_priority_slots(deployment_group) do
    # Just in case inflight goes higher than concurrent, limit it to 0
    (deployment_group.priority_queue_concurrent_updates -
       Devices.count_inflight_priority_updates_for(deployment_group))
    |> max(0)
    |> round()
  end

  @doc """
  Determine how many devices should update based on
  the deployment update limit and the number currently updating
  """
  @spec available_slots(DeploymentGroup.t()) :: non_neg_integer()
  def available_slots(deployment_group) do
    # Just in case inflight goes higher than concurrent, limit it to 0
    (deployment_group.concurrent_updates - Devices.count_inflight_updates_for(deployment_group))
    |> max(0)
    |> round()
  end

  @doc """
  Given a list of devices, confirm they haven't had too many update failures, then
  message the devices to schedule their updates, or update their `blocked_until`.

  Returns the number of devices that were allowed to update.
  """
  @spec schedule_devices!([Device.t()], DeploymentGroup.t(), boolean()) :: non_neg_integer()
  def schedule_devices!(available, deployment_group, priority_queue \\ false) do
    Enum.count(available, fn device ->
      case can_device_update?(device, deployment_group) do
        true ->
          tell_device_to_update(device.id, deployment_group, priority_queue)

        false ->
          _ = Devices.update_blocked_until(device, deployment_group)
          false
      end
    end)
  end

  @spec can_device_update?(Device.t(), DeploymentGroup.t()) :: boolean()
  defp can_device_update?(device, deployment_group) do
    not (Devices.failure_rate_met?(device, deployment_group) or
           Devices.failure_threshold_met?(device, deployment_group))
  end

  @spec tell_device_to_update(integer(), DeploymentGroup.t(), boolean()) :: boolean()
  defp tell_device_to_update(device_id, deployment_group, priority_queue) do
    :telemetry.execute([:nerves_hub, :deployments, :trigger_update, :device], %{count: 1})

    case Devices.told_to_update(device_id, deployment_group, priority_queue: priority_queue) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # if rate limiting isn't enabled, run `trigger_update`
  defp maybe_trigger_update(%State{rate_limit?: false} = state) do
    deployment_group = trigger_update(state.deployment_group)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  # if there is no "delay" timer set, run `trigger_update`
  defp maybe_trigger_update(%State{timer_ref: nil} = state) do
    deployment_group = trigger_update(state.deployment_group)

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
    deployment_group = trigger_update(state.deployment_group)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  # we can ignore `trigger_interval` since we have a `timer_ref`
  def handle_info(:trigger_interval, state) do
    {:noreply, state}
  end

  # if the 'run again' boolean in the state is `true`, which indicates that indicates
  # that previous call has been skipped, then run `trigger_update` now
  def handle_info(:maybe_trigger, %State{rate_limit?: false} = state) do
    deployment_group = trigger_update(state.deployment_group)

    {:noreply, %{state | deployment_group: deployment_group}}
  end

  def handle_info(:maybe_trigger, %State{should_run?: true} = state) do
    deployment_group = trigger_update(state.deployment_group)

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

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployment/device-update")
  def handle_info(%Broadcast{topic: "orchestrator:deployment:" <> _, event: "device-updated"}, state) do
    maybe_trigger_update(state)
  end

  @decorate with_span("ManagedDeployments.Distributed.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{topic: "deployment:" <> _, event: "deployments/update"}, state) do
    {:ok, deployment_group} = ManagedDeployments.get_deployment_group(state.deployment_group)
    maybe_trigger_update(%{state | deployment_group: deployment_group})
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
    not (firmware_match?(payload, deployment_group) or updates_blocked?(payload))
  end

  defp firmware_match?(payload, deployment_group) do
    payload.firmware_uuid == deployment_group.firmware.uuid
  end

  defp updates_blocked?(payload) do
    !payload.updates_enabled and
      !is_nil(payload.updates_blocked_until) and
      DateTime.after?(payload.updates_blocked_until, DateTime.utc_now())
  end
end
