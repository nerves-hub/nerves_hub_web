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

  def child_spec(deployment, rate_limit \\ true) do
    %{
      id: :"distributed_orchestrator_#{deployment.id}",
      start: {__MODULE__, :start_link, [deployment, rate_limit]}
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

    {:ok, {deployment, rate_limit, nil, true}}
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
  end

  @doc """
  Given a list of devices, confirm they haven't had too many update failures, then
  message the devices to schedule their updates, or update their `blocked_until`.

  Returns the number of devices that were allowed to update.
  """
  @spec schedule_devices!([Device.t()], Deployment.t()) :: non_neg_integer()
  def schedule_devices!(available, deployment) do
    available
    |> Enum.filter(fn device ->
      case can_device_update?(device, deployment) do
        true ->
          tell_device_to_update(device.id, deployment)

        false ->
          Devices.update_blocked_until(device, deployment)
          false
      end
    end)
    |> Enum.count()
  end

  @spec can_device_update?(Device.t(), Deployment.t()) :: boolean()
  defp can_device_update?(device, deployment) do
    not (Devices.failure_rate_met?(device, deployment) or
           Devices.failure_threshold_met?(device, deployment))
  end

  @spec tell_device_to_update(integer(), Deployment.t()) :: true
  defp tell_device_to_update(device_id, deployment) do
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update, :device], %{count: 1})

    Devices.told_to_update(device_id, deployment)

    true
  end

  # if there is not "delay" timer set, run `trigger_update`
  defp maybe_trigger_update({deployment, false, _, _run_again}) do
    trigger_update(deployment)

    {:noreply, {deployment, false, nil, false}}
  end

  # if there is not "delay" timer set, run `trigger_update`
  defp maybe_trigger_update({deployment, true, nil, _run_again}) do
    trigger_update(deployment)

    timer_ref = Process.send_after(self(), :maybe_trigger, 5_000)

    {:noreply, {deployment, true, timer_ref, false}}
  end

  # if a "delay" timer is set, queue a `trigger_update`
  # this is done by updating the last element of the state to `true`
  defp maybe_trigger_update({deployment, rate_limit, timer_ref, _run_again}) do
    {:noreply, {deployment, rate_limit, timer_ref, true}}
  end

  # this is the callback used by the timer
  def handle_info(:trigger_interval, {deployment, _rate_limit, timer_ref, _run_again} = state) do
    if is_nil(timer_ref) do
      trigger_update(deployment)
    end

    {:noreply, state}
  end

  # if the 'run again' boolean in the state is `true`, which indicates that indicates
  # that previous call has been skipped, then run `trigger_update` now
  def handle_info(:maybe_trigger, {deployment, rate_limit, _timer_ref, true}) do
    trigger_update(deployment)

    if rate_limit do
      timer_ref = Process.send_after(self(), :maybe_trigger, 5_000)

      {:noreply, {deployment, rate_limit, timer_ref, false}}
    else
      {:noreply, {deployment, rate_limit, nil, false}}
    end
  end

  # if the 'run again' boolean in the state is `false`, no requests to run the orchestrator
  # again have been received, so we can nil off the timer and move on
  def handle_info(:maybe_trigger, {deployment, rate_limit, _timer_ref, false}) do
    {:noreply, {deployment, rate_limit, nil, false}}
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployment/device-online")
  def handle_info(
        %Broadcast{
          topic: "orchestrator:deployment:" <> _rest,
          event: "device-online",
          payload: payload
        },
        {deployment, _rate_limit, _timer_ref, _run_again} = state
      ) do
    if payload.firmware_uuid != deployment.firmware.uuid do
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
        {deployment, rate_limit, timer_ref, run_again}
      ) do
    {:ok, deployment} = Deployments.get_deployment(deployment)

    maybe_trigger_update({deployment, rate_limit, timer_ref, run_again})
  end

  def handle_info(
        %Broadcast{topic: "deployment:" <> _, event: "deleted"},
        {deployment, _, _, _} = state
      ) do
    ProcessHub.stop_child(:deployment_orchestrators, :"distributed_orchestrator_#{deployment.id}")
    {:stop, :shutdown, state}
  end

  def handle_info(
        %Broadcast{topic: "orchestrator:deployment:" <> _, event: "deactivated"},
        {deployment, _, _, _} = state
      ) do
    ProcessHub.stop_child(:deployment_orchestrators, :"distributed_orchestrator_#{deployment.id}")
    {:stop, :shutdown, state}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, state) do
    {:noreply, state}
  end

  def handle_info(:trigger, state) do
    maybe_trigger_update(state)
  end

  def start_orchestrator(%Deployment{is_active: true} = deployment) do
    ProcessHub.start_child(:deployment_orchestrators, child_spec(deployment))
  end

  def start_orchestrator(_) do
    :ok
  end

  def stop_orchestrator(deployment) do
    Phoenix.Channel.Server.broadcast(
      NervesHub.PubSub,
      "orchestrator:deployment:#{deployment.id}",
      "deactivated",
      %{}
    )
  end
end
