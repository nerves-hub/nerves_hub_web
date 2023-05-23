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

    device =
      Enum.find(devices, fn device ->
        device.firmware_uuid != deployment.firmware.uuid
      end)

    if device && Devices.count_inflight_updates_for(deployment) < deployment.concurrent_updates do
      %{device_id: device_id, pid: pid} = device

      device = %Device{id: device_id}

      case Devices.told_to_update(device, deployment) do
        {:ok, inflight_update} ->
          send(pid, {"deployments/update", inflight_update})

        {:error, _changeset} ->
          Logger.error("Could not update device #{device_id}")
      end

      send(self(), :trigger)
    end
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
