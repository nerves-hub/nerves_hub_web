defmodule NervesHub.ManagedDeployments.Orchestrator do
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

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.DeploymentGroup

  alias NervesHub.Repo

  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  def start_link(deployment_group) do
    GenServer.start_link(__MODULE__, deployment_group, name: name(deployment_group))
  end

  def name(deployment_id) when is_integer(deployment_id) do
    {:via, Registry, {ManagedDeployments, deployment_id}}
  end

  def name(deployment_group), do: name(deployment_group.id)

  def device_updated(deployment_id) do
    GenServer.cast(name(deployment_id), :trigger)
  end

  @doc """
  Trigger an update for a device on the local node

  Finds a device matching:

  - the deployment
  - not updating
  - not using the deployment group's current firmware

  If there is space for the device based on the concurrent allowed updates
  the device is told to update. This is not guaranteed to be at or under the
  concurrent limit, it's a best effort.

  As devices update and reconnect, the new orchestrator is told that the update
  was successful, and the process is repeated.
  """
  @decorate with_span("ManagedDeployments.Orchestrator.trigger_update#noop")
  def trigger_update(%DeploymentGroup{is_active: false}) do
    :ok
  end

  @decorate with_span("ManagedDeployments.Orchestrator.trigger_update#noop")
  def trigger_update(%DeploymentGroup{orchestrator_strategy: strategy}) when strategy != :multi do
    :ok
  end

  @decorate with_span("ManagedDeployments.Orchestrator.trigger_update")
  def trigger_update(deployment_group) do
    :telemetry.execute([:nerves_hub, :deployments, :trigger_update], %{count: 1})

    match_conditions = [
      {:and, {:==, {:map_get, :deployment_id, :"$1"}, deployment_group.id},
       {:==, {:map_get, :updating, :"$1"}, false},
       {:==, {:map_get, :updates_enabled, :"$1"}, true}}
    ]

    match_return = %{
      device_id: {:element, 1, :"$_"},
      pid: {:element, 1, {:element, 2, :"$_"}},
      firmware_uuid: {:map_get, :firmware_uuid, {:element, 2, {:element, 2, :"$_"}}}
    }

    devices =
      Registry.select(Devices.Registry, [
        {{:_, :_, :"$1"}, match_conditions, [match_return]}
      ])

    # Get a rough count of devices to update
    count =
      deployment_group.concurrent_updates - Devices.count_inflight_updates_for(deployment_group)

    # Just in case inflight goes higher than concurrent, limit it to 0
    count = max(count, 0)

    # use a reduce to bounce out early?
    # limit the number of devices to 5 minutes / 500ms?

    devices
    |> Enum.take(count)
    |> Enum.each(fn %{device_id: device_id, pid: pid} ->
      :telemetry.execute([:nerves_hub, :deployments, :trigger_update, :device], %{count: 1})

      device = %Device{id: device_id}

      # Check again because other nodes are processing at the same time
      if Devices.count_inflight_updates_for(deployment_group) <
           deployment_group.concurrent_updates do
        case Devices.told_to_update(device, deployment_group, pid) do
          {:ok, _inflight_update} ->
            :ok

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

  def init(deployment_group) do
    {:ok, deployment_group, {:continue, :boot}}
  end

  @decorate with_span("ManagedDeployments.Orchestrator.boot")
  def handle_continue(:boot, deployment_group) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment_group.id}")

    # trigger every 10 minutes, plus a jitter between 1 and 5 seconds, as a back up
    interval = (10 + :rand.uniform(10)) * 60 * 1000
    _ = :timer.send_interval(interval, :trigger)

    deployment_group = Repo.reload(deployment_group)

    {:noreply, deployment_group}
  end

  def handle_cast(:trigger, deployment_group) do
    trigger_update(deployment_group)
    {:noreply, deployment_group}
  end

  @decorate with_span("ManagedDeployments.Orchestrator.handle_info:deployments/update")
  def handle_info(%Broadcast{event: "deployments/update"}, deployment_group) do
    deployment_group = Repo.reload(deployment_group)

    trigger_update(deployment_group)

    {:noreply, deployment_group}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, deployment_group),
    do: {:noreply, deployment_group}

  def handle_info(:trigger, deployment_group) do
    trigger_update(deployment_group)
    {:noreply, deployment_group}
  end
end
