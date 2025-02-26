defmodule NervesHub.Deployments.Distributed.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestrator will fetch online
  devices in the assigned deployment that need to be updated and send
  pubsub messages to their device channel requesting they be updated.
  """

  use GenServer
  use OpenTelemetryDecorator

  require Logger

  alias NervesHub.Deployments
  alias NervesHub.Deployments.Deployment
  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @maybe_trigger_interval 3_000

  defmodule State do
    defstruct deployment: nil,
              rate_limit?: true,
              timer_ref: nil,
              should_run?: false

    @type t ::
            %__MODULE__{
              deployment: Deployment.t(),
              rate_limit?: boolean(),
              timer_ref: reference() | nil,
              should_run?: boolean()
            }
  end

  def child_spec(deployment, rate_limit \\ true) do
    %{
      id: :"distributed_orchestrator_#{deployment.id}",
      start: {__MODULE__, :start_link, [deployment, rate_limit]},
      restart: :transient
    }
  end

  def start_link(deployment, rate_limit) do
    GenServer.start_link(__MODULE__, {deployment, rate_limit})
  end

  def start_link(deployment) do
    start_link(deployment, true)
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.init")
  def init({deployment, rate_limit}) do
    :ok = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")
    :ok = PubSub.subscribe(NervesHub.PubSub, "orchestrator:deployment:#{deployment.id}")

    # trigger every two minutes, plus a jitter between 1 and 10 seconds, as a back up
    interval = :timer.seconds(120 + :rand.uniform(20))
    _ = :timer.send_interval(interval, :trigger_interval)

    {:ok, deployment} = Deployments.get_deployment(deployment)

    send(self(), :maybe_trigger)

    state = %State{
      deployment: deployment,
      rate_limit?: rate_limit,
      timer_ref: nil,
      should_run?: true
    }

    {:ok, state}
  end

  @doc """
  Trigger an update for a deployments devices.

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
  @decorate with_span("Deployments.Distributed.Orchestrator.trigger_update#noop")
  def trigger_update(%Deployment{is_active: false}) do
    :ok
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.trigger_update")
  def trigger_update(deployment) do
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update], %{count: 1})

    slots = available_slots(deployment)

    if slots > 0 do
      available = Devices.available_for_update(deployment, slots)

      updated_count = schedule_devices!(available, deployment)

      if length(available) != updated_count do
        # rerun the deployment check since some devices were skipped
        send(self(), :trigger)
      end
    end
  end

  @doc """
  Determine how many devices should update based on
  the deployment update limit and the number currently updating
  """
  @spec available_slots(Deployment.t()) :: non_neg_integer()
  def available_slots(deployment) do
    # Just in case inflight goes higher than concurrent, limit it to 0
    (deployment.concurrent_updates - Devices.count_inflight_updates_for(deployment))
    |> max(0)
    |> round()
  end

  @doc """
  Given a list of devices, confirm they haven't had too many update failures, then
  message the devices to schedule their updates, or update their `blocked_until`.

  Returns the number of devices that were allowed to update.
  """
  @spec schedule_devices!([Device.t()], Deployment.t()) :: non_neg_integer()
  def schedule_devices!(available, deployment) do
    Enum.count(available, fn device ->
      case can_device_update?(device, deployment) do
        true ->
          tell_device_to_update(device.id, deployment)

        false ->
          _ = Devices.update_blocked_until(device, deployment)
          false
      end
    end)
  end

  @spec can_device_update?(Device.t(), Deployment.t()) :: boolean()
  defp can_device_update?(device, deployment) do
    not (Devices.failure_rate_met?(device, deployment) or
           Devices.failure_threshold_met?(device, deployment))
  end

  @spec tell_device_to_update(integer(), Deployment.t()) :: boolean()
  defp tell_device_to_update(device_id, deployment) do
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update, :device], %{count: 1})

    case Devices.told_to_update(device_id, deployment) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # if rate limiting isn't enabled, run `trigger_update`
  defp maybe_trigger_update(%State{rate_limit?: false} = state) do
    trigger_update(state.deployment)

    {:noreply, state}
  end

  # if there is no "delay" timer set, run `trigger_update`
  defp maybe_trigger_update(%State{timer_ref: nil} = state) do
    trigger_update(state.deployment)

    timer_ref = Process.send_after(self(), :maybe_trigger, @maybe_trigger_interval)

    {:noreply, %{state | timer_ref: timer_ref, should_run?: false}}
  end

  # if a "delay" timer is set, queue a `trigger_update`
  # since the function above checks for a nil `timer_ref`, we can assume we have one here
  defp maybe_trigger_update(state) do
    {:noreply, %{state | should_run?: true}}
  end

  # if we don't have a `timer_ref` we can run `trigger_update`
  def handle_info(:trigger_interval, %State{timer_ref: nil} = state) do
    trigger_update(state.deployment)

    {:noreply, state}
  end

  # we can ignore `trigger_interval` since we have a `timer_ref`
  def handle_info(:trigger_interval, state) do
    {:noreply, state}
  end

  # if the 'run again' boolean in the state is `true`, which indicates that indicates
  # that previous call has been skipped, then run `trigger_update` now
  def handle_info(:maybe_trigger, %State{rate_limit?: false} = state) do
    trigger_update(state.deployment)

    {:noreply, state}
  end

  def handle_info(:maybe_trigger, %State{should_run?: true} = state) do
    trigger_update(state.deployment)

    timer_ref = Process.send_after(self(), :maybe_trigger, @maybe_trigger_interval)

    {:noreply, %{state | timer_ref: timer_ref, should_run?: false}}
  end

  # if the 'run again' boolean in the state is `false`, no requests to run the orchestrator
  # again have been received, so we can nil off the timer and move on
  def handle_info(:maybe_trigger, state) do
    {:noreply, %{state | timer_ref: nil}}
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployment/device-online")
  def handle_info(
        %Broadcast{
          topic: "orchestrator:deployment:" <> _rest,
          event: "device-online",
          payload: payload
        },
        state
      ) do
    if should_trigger?(payload, state.deployment) do
      maybe_trigger_update(state)
    else
      {:noreply, state}
    end
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployment/device-update")
  def handle_info(
        %Broadcast{topic: "orchestrator:deployment:" <> _, event: "device-updated"},
        state
      ) do
    maybe_trigger_update(state)
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployments/update")
  def handle_info(
        %Broadcast{topic: "deployment:" <> _, event: "deployments/update"},
        state
      ) do
    {:ok, deployment} = Deployments.get_deployment(state.deployment)

    # shutdown the orchestrator if the deployment is updated to use the old `:multi` strategy
    if deployment.orchestrator_strategy == :distributed do
      maybe_trigger_update(%{state | deployment: deployment})
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(%Broadcast{topic: "deployment:" <> _, event: "deleted"}, state) do
    {:stop, :normal, state}
  end

  def handle_info(%Broadcast{topic: "orchestrator:deployment:" <> _, event: "deactivated"}, state) do
    {:stop, :normal, state}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, state) do
    {:noreply, state}
  end

  def handle_info(:trigger, state) do
    maybe_trigger_update(state)
  end

  def start_orchestrator(
        %Deployment{is_active: true, orchestrator_strategy: :distributed} = deployment
      ) do
    if Application.get_env(:nerves_hub, :deploy_env) != "test" do
      ProcessHub.start_child(:deployment_orchestrators, child_spec(deployment))
    end
  end

  def start_orchestrator(_) do
    :ok
  end

  defp should_trigger?(payload, deployment) do
    not (firmware_match?(payload, deployment) or updates_blocked?(payload))
  end

  defp firmware_match?(payload, deployment) do
    payload.firmware_uuid == deployment.firmware.uuid
  end

  defp updates_blocked?(payload) do
    !payload.updates_enabled and
      !is_nil(payload.updates_blocked_until) and
      DateTime.compare(payload.updates_blocked_until, DateTime.utc_now()) == :gt
  end
end
