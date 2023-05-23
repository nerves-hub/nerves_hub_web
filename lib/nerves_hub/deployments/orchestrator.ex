defmodule NervesHub.Deployments.Orchestrator do
  @moduledoc """
  Orchestration process to handle passing out updates to devices

  When a deployment is updated, the orchestraor will tell every
  device local to its node that there is a new update. This will
  hook will allow the orchestrator to start slowly handing out
  updates instead of blasting every device at once.
  """

  use GenServer

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Repo
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  def start_link(deployment) do
    GenServer.start_link(__MODULE__, deployment, name: name(deployment))
  end

  def name(deployment_id) when is_integer(deployment_id) do
    {:via, Registry, {NervesHub.Deployments, deployment_id}}
  end

  def name(deployment), do: name(deployment.id)

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
  def trigger_update(deployment) do
    match_return = %{
      device_id: {:element, 1, :"$_"},
      pid: {:element, 1, {:element, 2, :"$_"}},
      firmware_uuid: {:map_get, :firmware_uuid, {:element, 2, {:element, 2, :"$_"}}}
    }

    devices =
      Registry.select(NervesHub.Devices, [
        {{:_, :_, %{deployment_id: deployment.id, updating: false}}, [], [match_return]}
      ])

    devices =
      Enum.filter(devices, fn device ->
        device.firmware_uuid != deployment.firmware.uuid
      end)

    # Get a rough count of devices to update
    count = deployment.concurrent_updates - Devices.count_inflight_updates_for(deployment)

    devices
    |> Enum.take(count)
    |> Enum.each(fn %{device_id: device_id, pid: pid} ->
      device = %Device{id: device_id}

      # Check again because other nodes are processing at the same time
      if Devices.count_inflight_updates_for(deployment) < deployment.concurrent_updates do
        case Devices.told_to_update(device, deployment) do
          {:ok, inflight_update} ->
            send(pid, {"deployments/update", inflight_update})

          :error ->
            Logger.error(
              "An inflight update could not be created or found for the device #{device.identifier} (#{device.id})"
            )
        end
      end

      # Slow the update a bit to allow for concurrent nodes
      Process.sleep(500)
    end)
  end

  def init(deployment) do
    {:ok, deployment, {:continue, :boot}}
  end

  def handle_continue(:boot, deployment) do
    PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    # trigger every 5 minutes as a back up
    :timer.send_interval(5 * 60 * 1000, :trigger)

    deployment =
      deployment
      |> Repo.reload()
      |> Repo.preload([:firmware], force: true)

    {:noreply, deployment}
  end

  def handle_cast(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, deployment) do
    deployment =
      deployment
      |> Repo.reload()
      |> Repo.preload([:firmware], force: true)

    trigger_update(deployment)

    {:noreply, deployment}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment), do: {:noreply, deployment}

  def handle_info(:trigger, deployment) do
    trigger_update(deployment)
    {:noreply, deployment}
  end
end
