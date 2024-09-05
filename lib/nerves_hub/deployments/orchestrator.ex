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
  alias NervesHub.Firmwares
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

  def report_version(deployment_id, firmware_uuid) when is_integer(deployment_id) do
    GenServer.cast(name(deployment_id), {:report, firmware_uuid})
  end

  @doc """
  Trigger an update for a device on the local node

  Finds a device matching:

  - the deployment
  - not updating
  - not using the deployment's current firmware
  - with deltas active: not currently being generated

  If there is space for the device based on the concurrent allowed updates
  the device is told to update. This is not guaranteed to be at or under the
  concurrent limit, it's a best effort.

  As devices update and reconnect, the new orchestrator is told that the update
  was successful, and the process is repeated.
  """
  def trigger_update(%{deployment: deployment} = state) do
    deployment = Repo.preload(deployment, [:product, :firmware])
    :telemetry.execute([:nerves_hub, :deployment, :trigger_update], %{count: 1})

    match_conditions = [
      {:and, {:==, {:map_get, :deployment_id, :"$1"}, deployment.id},
       {:==, {:map_get, :updating, :"$1"}, false},
       {:==, {:map_get, :updates_enabled, :"$1"}, true},
       {:"/=", {:map_get, :firmware_uuid, :"$1"}, deployment.firmware.uuid}}
    ]

    match_conditions =
      if deployment.product.delta_updatable do
        processing_deltas =
          for {firmware_uuid, :processing} <- state.delta_status do
            # Build rule to skip each firmware_uuid that is currently in delta processing
            {:"/=", {:map_get, :firmware_uuid, :"$1"}, firmware_uuid}
          end

        match_conditions ++ processing_deltas
      else
        match_conditions
      end

    match_return = %{
      device_id: {:element, 1, :"$_"},
      pid: {:element, 1, {:element, 2, :"$_"}},
      firmware_uuid: {:map_get, :firmware_uuid, {:element, 2, {:element, 2, :"$_"}}}
    }

    devices =
      Registry.select(NervesHub.Devices, [
        {{:_, :_, :"$1"}, match_conditions, [match_return]}
      ])

    # Get a rough count of devices to update
    count = deployment.concurrent_updates - Devices.count_inflight_updates_for(deployment)
    # Just in case inflight goes higher than concurrent, limit it to 0
    count = max(count, 0)

    # use a reduce to bounce out early?
    # limit the number of devices to 5 minutes / 500ms?

    devices
    |> Enum.take(count)
    |> Enum.each(fn %{device_id: device_id, pid: pid} ->
      :telemetry.execute([:nerves_hub, :deployment, :trigger_update, :device], %{count: 1})

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
    state = %{
      # fw_uuid => {:ready, FirmwareDelta.t()} | :processing | :needs_full
      delta_status: %{},
      deployment: deployment
    }

    {:ok, state, {:continue, :boot}}
  end

  def handle_continue(:boot, %{deployment: deployment} = state) do
    _ = PubSub.subscribe(NervesHub.PubSub, "deployment:#{deployment.id}")

    # trigger every 5 minutes as a back up
    _ = :timer.send_interval(5 * 60 * 1000, :trigger)

    deployment =
      deployment
      |> Repo.reload()
      |> Repo.preload([:firmware, []], force: true)
      |> Repo.preload([:product], force: true)

    {:noreply, %{state | deployment: deployment}}
  end

  def handle_cast(:trigger, state) do
    trigger_update(state)
    {:noreply, state}
  end

  def handle_cast({:report, firmware_uuid}, %{deployment: deployment} = state) do
    # Are delta updates enabled?
    state =
      if firmware_uuid != deployment.firmware.uuid and deployment.product.delta_updatable do
        ensure_delta_resolved(state, firmware_uuid)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, %{deployment: deployment} = state) do
    deployment =
      deployment
      |> Repo.reload()
      |> Repo.preload([:firmware], force: true)

    state = %{state | deployment: deployment}
    trigger_update(state)

    {:noreply, state}
  end

  # Catch all for unknown broadcasts on a deployment
  def handle_info(%Broadcast{topic: "deployment:" <> _}, %{deployment: deployment} = state),
    do: {:noreply, %{state | deployment: deployment}}

  def handle_info(:trigger, state) do
    trigger_update(state)
    {:noreply, state}
  end

  defp ensure_delta_resolved(%{deployment: deployment} = state, firmware_uuid) do
    # Do we need to figure out what the delta status is?
    if is_nil(state.delta_status[firmware_uuid]) do
      # Does the source version exist as firmware for this deployment?
      # Otherwise generating a delta is impossible.
      case Firmwares.get_firmware_by_product_and_uuid(deployment.product, firmware_uuid) do
        {:ok, source_fw} ->
          attempt_resolve_delta(state, source_fw)

        {:error, _} ->
          Logger.warning(
            "Cannot trigger firmware delta generation from #{firmware_uuid}. Firmware does not exist for Deployment ID #{deployment.id}."
          )

          set_delta_status(state, firmware_uuid, :needs_full)
      end
    else
      # Do nothing if already resolved
      state
    end
  end

  defp attempt_resolve_delta(state, source_fw) do
    case Firmwares.get_firmware_delta_by_source_and_target(source_fw, state.deployment.firmware) do
      {:ok, fw_delta} ->
        set_delta_status(state, source_fw.uuid, {:ready, fw_delta})

      {:error, :not_found} ->
        NervesHub.Workers.FirmwareDeltaBuilder.start(source_fw.id, state.deployment.firmware.id)
        set_delta_status(state, source_fw.uuid, :processing)
    end
  end

  defp set_delta_status(state, firmware_uuid, status) do
    put_in(state, [:delta_status, firmware_uuid], status)
  end
end
