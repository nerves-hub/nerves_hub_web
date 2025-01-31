defmodule NervesHub.Deployments.Distributed.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestrator will tell every
  device local to its node that there is a new update. This
  hook will allow the orchestrator to start slowly handing out
  updates instead of blasting every device at once.
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

  def child_spec(deployment) do
    %{
      id: "#{__MODULE__}_#{deployment.id}",
      start: {__MODULE__, :start_link, [deployment]},
      shutdown: 10_000,
      restart: :transient
    }
  end

  def start_link(deployment) do
    case GenServer.start_link(__MODULE__, deployment, name: name(deployment.id)) do
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

  def name(deployment_id) do
    {:via, Horde.Registry, {NervesHub.DeploymentsRegistry, deployment_id}}
  end

  def device_updated(deployment_id) do
    GenServer.cast(name(deployment_id), :trigger)
  end

  @doc """
  Trigger an update for a device on the local node

  Finds a device matching:

  - the deployment
  - not updating
  - not using the deployment's current firmware

  If there is space for the device based on the concurrent allowed updates
  the device is told to update. This is not guaranteed to be at or under the
  concurrent limit, it's a best effort.

  As devices update and reconnect, the new orchestrator is told that the update
  was successful, and the process is repeated.
  """
  @decorate with_span("Deployments.Orchestrator.trigger_update#noop")
  def trigger_update(%Deployment{is_active: false}) do
    :ok
  end

  @decorate with_span("Deployments.Orchestrator.trigger_update")
  def trigger_update(deployment) do
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update], %{count: 1})

    # Get a rough count of devices to update
    count = deployment.concurrent_updates - Devices.count_inflight_updates_for(deployment)
    # Just in case inflight goes higher than concurrent, limit it to 0
    count = max(count, 0)

    if count > 0 do
      devices = Devices.available_for_update(deployment, count)

      devices
      |> Enum.each(fn %{device_id: device_id} ->
        :telemetry.execute([:nerves_hub, :deployment, :trigger_update, :device], %{count: 1})

        device = %Device{id: device_id}

        case Devices.told_to_update(device, deployment) do
          {:ok, inflight_update} ->
            message = %Phoenix.Socket.Broadcast{
              topic: "device:#{device.id}",
              event: "update-scheduled",
              payload: inflight_update
            }

            Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", message)

          :error ->
            Logger.error(
              "An inflight update could not be created or found for the device #{device.identifier} (#{device.id})"
            )
        end
      end)
    end
  end

  def init(deployment) do
    {:ok, deployment, {:continue, :boot}}
  end

  @decorate with_span("Deployments.Orchestrator.boot")
  def handle_continue(:boot, deployment) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    # trigger every minute, plus a jitter between 1 and 10 seconds, as a back up
    interval = :timer.seconds(60 + :rand.uniform(10))
    _ = :timer.send_interval(interval, :trigger)

    {:ok, deployment} = Deployments.get_deployment(deployment)

    send(self(), :trigger)

    {:noreply, deployment}
  end

  def handle_cast(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  @decorate with_span("Deployments.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{event: "deployment/device-updated"}, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  @decorate with_span("Deployments.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{event: "deployments/update"}, deployment) do
    {:ok, deployment} = Deployments.get_deployment(deployment)

    trigger_update(deployment)

    {:noreply, deployment}
  end

  def handle_info(%Broadcast{event: "deployments/deleted"}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info(%Broadcast{event: "deployments/deactivated"}, state) do
    {:stop, :shutdown, state}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment), do: {:noreply, deployment}

  def handle_info(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end
end
