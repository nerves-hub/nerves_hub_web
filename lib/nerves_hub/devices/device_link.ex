defmodule NervesHub.Devices.DeviceLink do
  @moduledoc """
  GenServer to track a connected device

  Contains logic for a device separate from the transport layer,
  e.g. websockets, MQTT, etc
  """

  # NOTE: revisit this restart strategy as we add in more
  # transport layers for devices, such as MQTT
  use GenServer, restart: :transient

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  require Logger

  defmodule State do
    defstruct [
      :deployment_channel,
      :device,
      :penalty_timer,
      :push_cb,
      :reference_id,
      :transport_pid,
      :transport_ref,
      :device_api_version,
      :update_started?
    ]
  end

  @spec start_link(Device.t()) :: GenServer.on_start()
  def start_link(device_id) do
    GenServer.start_link(__MODULE__, device_id, name: name(device_id))
  end

  @spec name(Device.t() | pos_integer()) ::
          {:via, Registry, {NervesHub.DeviceLinks, {:link, pos_integer()}}}
  def name(device_id) when is_integer(device_id) do
    {:via, Registry, {NervesHub.DeviceLinks, {:link, device_id}}}
  end

  def name(device), do: name(device.id)

  @spec whereis(pid() | Device.t()) :: pid() | nil
  def whereis(pid) when is_pid(pid), do: pid

  def whereis(%Device{} = device) do
    GenServer.whereis(name(device.id))
  end

  @doc """
  String version of `online?/1`
  """
  def status(device) do
    if online?(device) do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Check if a device is currently online

  Returns `false` immediately but sends a message to the device's channel asking if it's
  online. If the device is online, it will send a connection state change of online.
  """
  def online?(device) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.id}", :online?)
    false
  end

  @doc """
  Mark device as connected

  The transport of choice would call this function when it detects
  a device has connected to register a push callback which DeviceLink
  will use to push events through the transport back to the device.

  The push callback mush be arity 2 to accept an `event` and `payload`

  Optionally, you can tell DeviceLink to monitor the calling process
  to tie the DeviceLinks presence to the transport. This is mostly
  applicable to the websocket transport.

  Firmware metadata is expected to be a map with the following
  string keys:
    * `"nerves_fw_uuid"`
    * `"nerves_fw_architecture"`
    * `"nerves_fw_platform"`
    * `"nerves_fw_product"`
    * `"nerves_fw_version"`
    * `"nerves_fw_author"`
    * `"nerves_fw_description"`
    * "fwup_version"
    * `"nerves_fw_vcs_identifier"`
    * `"nerves_fw_misc"`
  """
  @type push_callback :: (String.t(), map() -> :ok)
  # TODO Maybe this should be atom keys so we can type it? ¬
  @type firmware_metadata :: map()
  @spec(
    connect(Device.t(), push_callback(), firmware_metadata(), monitor: String.t()) :: :ok,
    {:error, Ecto.Changeset.t()}
  )
  def connect(device, push_cb, params, opts \\ [])

  def connect(%Device{} = device, push_cb, params, opts) do
    link =
      case whereis(device) do
        nil ->
          {:ok, pid} = start_device(device)
          pid

        link ->
          link
      end

    connect(link, push_cb, params, opts)
  end

  def connect(link, push_cb, params, opts) when is_function(push_cb, 2) do
    monitor =
      case opts[:monitor] do
        ref when is_binary(ref) ->
          {self(), ref}

        _ ->
          nil
      end

    GenServer.call(link, {:connect, push_cb, params, monitor, :ctx})
  end

  defp start_device(device) do
    case GenServer.whereis(name(device)) do
      nil ->
        DynamicSupervisor.start_child(
          {:via, PartitionSupervisor, {NervesHub.Devices.Supervisors, self()}},
          {__MODULE__, device.id}
        )

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @doc """
  Mark device as disconnected

  For websocket transport, this will also close the DeviceLink process
  """
  def disconnect(link_or_pid) do
    if link = whereis(link_or_pid) do
      GenServer.call(link, :disconnect)
    else
      :ok
    end
  end

  @spec recv(GenServer.server(), String.t(), map()) :: :ok
  def recv(link, event, payload) do
    GenServer.call(link, {:receive, event, payload})
  end

  @impl GenServer
  def init(device_id) do
    {:ok, %State{}, {:continue, {:boot, device_id}}}
  end

  @impl GenServer
  def handle_continue({:boot, device_id}, state) do
    device = Devices.get_device(device_id)

    ref_id = Base.encode32(:crypto.strong_rand_bytes(2), padding: false)

    deployment_channel =
      if device.deployment_id do
        "deployment:#{device.deployment_id}"
      else
        "deployment:none"
      end

    subscribe("device:#{device.id}")
    subscribe(deployment_channel)

    # local node tracking
    Registry.register(NervesHub.Devices, device.id, %{
      deployment_id: device.deployment_id,
      firmware_uuid: get_in(device, [Access.key(:firmware_uuid), Access.key(:uuid)]),
      updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
      updating: false
    })

    {:noreply,
     %{state | device: device, deployment_channel: deployment_channel, reference_id: ref_id}}
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    {:stop, :normal, :ok, do_disconnect(state)}
  end

  def handle_call({:connect, push_cb, params, monitor, _ctx}, _from, %{device: device} = state) do
    with {:ok, device} <- update_metadata(device, params),
         {:ok, device} <- Devices.device_connected(device) do
      state = %{state | device_api_version: Map.get(params, "device_api_version", "1.0.0")}

      description = "device #{device.identifier} connected to the server"

      AuditLogs.audit_with_ref!(
        device,
        device,
        description,
        state.reference_id
      )

      device =
        device
        |> Devices.verify_deployment()
        |> Deployments.set_deployment()
        |> Repo.preload(deployment: [:archive, :firmware])

      # clear out any inflight updates, there shouldn't be one at this point
      # we might make a new one right below it, so clear it beforehand
      Devices.clear_inflight_update(device)

      # Let the orchestrator handle this going forward ?
      update_payload = Devices.resolve_update(device)

      push_update? =
        update_payload.update_available and not is_nil(update_payload.firmware_url) and
          update_payload.firmware_meta[:uuid] != params["currently_downloading_uuid"]

      if push_update? do
        # Push the update to the device
        push_cb.("update", update_payload)

        deployment = device.deployment

        description =
          "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} on connect"

        AuditLogs.audit_with_ref!(
          deployment,
          device,
          description,
          state.reference_id
        )

        # if there's an update, track it
        Devices.told_to_update(device, deployment)
      end

      ## After join
      :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1})

      # local node tracking
      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        update = %{
          deployment_id: device.deployment_id,
          firmware_uuid: device.firmware_metadata.uuid,
          updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
          updating: push_update?
        }

        Map.merge(value, update)
      end)

      publish_connection(device, "online")

      if Version.match?(state.device_api_version, ">= 2.0.0") do
        if device.deployment && device.deployment.archive do
          archive = device.deployment.archive

          push_cb.("archive", %{
            size: archive.size,
            uuid: archive.uuid,
            version: archive.version,
            description: archive.description,
            platform: archive.platform,
            architecture: archive.architecture,
            uploaded_at: archive.inserted_at,
            url: Archives.url(archive)
          })
        end
      end

      state =
        case monitor do
          {transport_pid, ref_id} ->
            ref = Process.monitor(transport_pid)
            %{state | reference_id: ref_id, transport_pid: transport_pid, transport_ref: ref}

          _ ->
            state
        end

      state =
        %{
          state
          | device: device,
            push_cb: push_cb,
            update_started?: push_update?
        }
        |> maybe_start_penalty_timer()

      {:reply, {:ok, self()}, state}
    else
      {:error, err} ->
        {:reply, {:error, err}, state}

      err ->
        {:reply, {:error, err}, state}
    end
  end

  def handle_call(
        {:receive, "fwup_progress", %{"value" => percent}},
        _from,
        %{device: device} = state
      ) do
    NervesHubWeb.DeviceEndpoint.broadcast_from!(
      self(),
      "device:#{device.identifier}:internal",
      "fwup_progress",
      %{
        percent: percent
      }
    )

    # if this is the first fwup we see, then mark it as an update attempt
    state =
      if !state.update_started? do
        # reload update attempts because they might have been cleared
        # and we have a cached stale version
        updated_device = Repo.reload(device)
        device = %{device | update_attempts: updated_device.update_attempts}

        {:ok, device} = Devices.update_attempted(device)

        Registry.update_value(NervesHub.Devices, device.id, fn value ->
          Map.put(value, :updating, true)
        end)

        %{state | device: device, update_started?: true}
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:receive, "status_update", %{"status" => _status}}, _from, state) do
    # TODO store in tracker or the database?
    {:reply, :ok, state}
  end

  def handle_call({:receive, "rebooting", _}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(
        {:receive, "connection_types", %{"values" => types}},
        _from,
        %{device: device} = state
      ) do
    {:ok, device} = Devices.update_device(device, %{"connection_types" => types})
    {:reply, :ok, %{state | device: device}}
  end

  def handle_call({:receive, _event, _payload}, _from, state) do
    {:reply, {:error, :unhandled}, state}
  end

  @impl GenServer
  def handle_info({:DOWN, transport_ref, :process, _pid, _reason}, state) do
    if state.transport_ref == transport_ref do
      {:stop, :normal, do_disconnect(state)}
    else
      # TCP sockets have longer timeouts. There is a chance the old socket
      # was still around when the new one started which could result in
      # getting this message later than expected
      #
      # For cases like that and when we no longer know the ref, simply ignore
      {:noreply, state}
    end
  end

  # We can save a fairly expensive query by checking the incoming deployment's payload
  # If it matches, we can set the deployment directly and only do 3 queries (update, two preloads)
  def handle_info(
        %Broadcast{event: "deployments/changed", topic: "deployment:none", payload: payload},
        %{device: device} = state
      ) do
    if device_matches_deployment_payload?(device, payload) do
      {:noreply, assign_deployment(state, payload)}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        %Broadcast{event: "deployments/changed", payload: payload},
        %{device: device} = state
      ) do
    if device_matches_deployment_payload?(device, payload) do
      :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})
      {:noreply, assign_deployment(state, payload)}
    else
      # jitter over a minute but spaced out to attempt to not
      # slam the database when all devices check
      jitter = :rand.uniform(30) * 2 * 1000
      Process.send_after(self(), :resolve_changed_deployment, jitter)
      {:noreply, state}
    end
  end

  def handle_info(:resolve_changed_deployment, %{device: device} = state) do
    :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})

    device =
      device
      |> Repo.reload()
      |> Deployments.set_deployment()
      |> Repo.preload([deployment: [:firmware]], force: true)

    description =
      if device.deployment_id do
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"
      else
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"
      end

    AuditLogs.audit_with_ref!(
      device,
      device,
      description,
      state.reference_id
    )

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    {:noreply, update_device(state, device)}
  end

  # manually pushed
  def handle_info(
        %Broadcast{event: "deployments/update", payload: %{deployment_id: nil} = payload},
        state
      ) do
    :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})
    state.push_cb.("update", payload)
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, state) do
    {:noreply, state}
  end

  def handle_info({"deployments/update", inflight_update}, %{device: device} = state) do
    :telemetry.execute([:nerves_hub, :devices, :update, :automatic], %{count: 1})

    device = Repo.preload(device, [deployment: [:firmware]], force: true)

    payload = Devices.resolve_update(device)

    case payload.update_available do
      true ->
        deployment = device.deployment
        firmware = deployment.firmware

        description =
          "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{firmware.uuid}"

        # If we get here, the device is connected and high probability it receives
        # the update message so we can Audit and later assert on this audit event
        # as a loosely valid attempt to update
        AuditLogs.audit_with_ref!(
          deployment,
          device,
          description,
          state.reference_id
        )

        Devices.update_started!(inflight_update)
        state.push_cb.("update", payload)

        {:noreply, state}

      false ->
        {:noreply, state}
    end
  end

  def handle_info(%Broadcast{event: "moved"}, state) do
    # The old deployment is no longer valid, so let's look one up again
    handle_info(:resolve_changed_deployment, state)
  end

  # Update local state and tell the various servers of the new information
  def handle_info(%Broadcast{event: "devices/updated"}, %{device: device} = state) do
    device = Repo.reload(device)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.merge(value, %{
        updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device)
      })
    end)

    state =
      state
      |> update_device(device)
      |> maybe_start_penalty_timer()

    {:noreply, state}
  end

  def handle_info(:online?, state) do
    publish_connection(state.device, "online")
    {:noreply, state}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, state) do
    # Forward broadcasts to the device for now
    state.push_cb.(event, payload)
    {:noreply, state}
  end

  def handle_info(:penalty_box_check, %{device: device} = state) do
    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)

    :telemetry.execute([:nerves_hub, :devices, :penalty_box, :check], %{
      updates_enabled: updates_enabled
    })

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.merge(value, %{updates_enabled: updates_enabled})
    end)

    # Just in case time is weird or it got placed back in between checks
    state =
      if !updates_enabled do
        maybe_start_penalty_timer(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning("[DeviceLink] Unhandled message! - #{inspect(msg)}")

    _ =
      Sentry.capture_message("[DeviceLink] Unhandled message!",
        extra: %{message: msg},
        result: :none
      )

    {:noreply, state}
  end

  defp subscribe(topic) do
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
  end

  defp unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  # The reported firmware is the same as what we already know about
  def update_metadata(%Device{firmware_metadata: %{uuid: uuid}} = device, %{
        "nerves_fw_uuid" => uuid
      }) do
    {:ok, device}
  end

  # A new UUID is being reported from an update
  def update_metadata(device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata) do
      Devices.firmware_update_successful(device)
    end
  end

  defp device_matches_deployment_payload?(device, payload) do
    payload.active &&
      device.product_id == payload.product_id &&
      device.firmware_metadata.platform == payload.platform &&
      device.firmware_metadata.architecture == payload.architecture &&
      Enum.all?(payload.conditions["tags"], &Enum.member?(device.tags, &1)) &&
      Deployments.version_match?(device, payload)
  end

  defp assign_deployment(%{device: device} = state, payload) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, payload.id)
      |> Repo.update!()
      |> Repo.preload([deployment: [:firmware]], force: true)

    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit_with_ref!(device, device, description, state.reference_id)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    update_device(state, device)
  end

  def update_device(state, device) do
    unsubscribe(state.deployment_channel)

    deployment_channel =
      if device.deployment_id do
        "deployment:#{device.deployment_id}"
      else
        "deployment:none"
      end

    subscribe(deployment_channel)
    %{state | device: device, deployment_channel: deployment_channel}
  end

  defp maybe_start_penalty_timer(%{device: %{updates_blocked_until: nil}} = state), do: state

  defp maybe_start_penalty_timer(state) do
    check_penalty_box_in =
      DateTime.diff(state.device.updates_blocked_until, DateTime.utc_now(), :millisecond)

    ref =
      if check_penalty_box_in > 0 do
        _ = if state.penalty_timer, do: Process.cancel_timer(state.penalty_timer)
        # delay the check slightly to make sure the penalty is cleared when its updated
        Process.send_after(self(), :penalty_box_check, check_penalty_box_in + 1000)
      end

    %{state | penalty_timer: ref}
  end

  defp do_disconnect(state) do
    _ =
      if state.transport_ref do
        Process.demonitor(state.transport_ref)
      end

    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1})

    {:ok, device} = Devices.update_device(state.device, %{last_communication: DateTime.utc_now()})

    description = "device #{device.identifier} disconnected from the server"

    AuditLogs.audit_with_ref!(device, device, description, state.reference_id)

    Registry.unregister(NervesHub.Devices, device.id)
    publish_connection(device, "offline")

    %{state | device: device, transport_pid: nil, transport_ref: nil}
  end

  defp publish_connection(device, status) do
    message = %Phoenix.Socket.Broadcast{
      event: "connection_change",
      payload: %{
        device_id: device.identifier,
        status: status
      }
    }

    Phoenix.PubSub.broadcast(NervesHub.PubSub, "device:#{device.identifier}:internal", message)

    :ok
  end
end
