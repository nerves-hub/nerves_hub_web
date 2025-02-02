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

  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  def child_spec(deployment) do
    %{
      id: :"distributed_orchestrator_#{deployment.id}",
      start: {__MODULE__, :start_link, [deployment]}
    }
  end

  def start_link(deployment) do
    case GenServer.start_link(__MODULE__, deployment) do
      {:ok, pid} ->
        Logger.info("Deployment orchestrator started", deployment_id: deployment.id)

        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        Logger.info("Deployment orchestrator already started, ignoring",
          deployment_id: deployment.id
        )

        :ignore
    end
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.init")
  def init(deployment) do
    :ok = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    # trigger every minute, plus a jitter between 1 and 10 seconds, as a back up
    interval = :timer.seconds(90 + :rand.uniform(20))
    _ = :timer.send_interval(interval, :trigger)

    {:ok, deployment} = Deployments.get_deployment(deployment)

    send(self(), :trigger)

    {:ok, deployment}
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
      Devices.available_for_update(deployment, slots)
      |> Enum.each(fn %{id: device_id} ->
        tell_device_to_update(device_id, deployment)
      end)
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

  @spec tell_device_to_update(integer(), Deployment.t()) :: :ok
  defp tell_device_to_update(device_id, deployment) do
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update, :device], %{count: 1})

    Devices.told_to_update(device_id, deployment)

    :ok
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.trigger")
  def handle_cast(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployment/device-online")
  def handle_info(%Broadcast{event: "deployment/device-online", payload: payload}, deployment) do
    if payload.firmware_uuid != deployment.firmware.uuid do
      trigger_update(deployment)
    end

    {:noreply, deployment}
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployment/device-update")
  def handle_info(%Broadcast{event: "deployment/device-updated"}, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  @decorate with_span("Deployments.Distributed.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{event: "deployments/update"}, deployment) do
    {:ok, deployment} = Deployments.get_deployment(deployment)

    trigger_update(deployment)

    {:noreply, deployment}
  end

  def handle_info(%Broadcast{event: "deployment/deleted"}, deployment) do
    ProcessHub.stop_child(:deployment_orchestrators, :"distributed_orchestrator_#{deployment.id}")
  end

  def handle_info(%Broadcast{event: "deployment/deactivated"}, deployment) do
    ProcessHub.stop_child(:deployment_orchestrators, :"distributed_orchestrator_#{deployment.id}")
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment) do
    {:noreply, deployment}
  end

  def handle_info(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  def start_orchestrator(%Deployment{is_active: true} = deployment) do
    ProcessHub.start_child(:deployment_orchestrators, child_spec(deployment))
  end

  def start_orchestrator(_) do
    :ok
  end

  def stop_orchestrator(deployment) do
    message = %Phoenix.Socket.Broadcast{
      topic: "deployment:#{deployment.id}",
      event: "deployment/deactivated"
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "deployment:#{deployment.id}", message)
  end
end
