defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  Handles device logic for updating and tracking devices
  """

  use Phoenix.Channel

  require Logger

  alias NervesHub.Archives
  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias Phoenix.Socket.Broadcast

  def join("device", params, %{assigns: %{device: device}} = socket) do
    with {:ok, device} <- update_metadata(device, params),
         {:ok, device} <- Devices.device_connected(device) do
      socket = assign(socket, :device_api_version, Map.get(params, "device_api_version", "1.0.0"))

      description = "device #{device.identifier} connected to the server"

      AuditLogs.audit_with_ref!(
        device,
        device,
        description,
        socket.assigns.reference_id
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
        push("update", update_payload)

        deployment = device.deployment

        description =
          "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} on connect"

        AuditLogs.audit_with_ref!(
          deployment,
          device,
          description,
          socket.assigns.reference_id
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

      # Cluster tracking
      Tracker.online(device)

      if Version.match?(socket.assigns.device_api_version, ">= 2.0.0") do
        if device.deployment && device.deployment.archive do
          archive = device.deployment.archive

          push("archive", %{
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

      socket =
        socket
        |> assign(:device, device)
        |> assign(:update_started?, push_update?)
        |> maybe_start_penalty_timer()

      send(self(), :boot)

      {:ok, socket}
    else
      err ->
        Logger.warning("[DeviceChannel] failure to connect - #{inspect(err)}")

        {:error, %{error: "could not connect"}}
    end
  end

  def handle_info(:boot, %{assigns: %{device: device}} = socket) do
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

    socket =
      socket
      |> assign(:device, device)
      |> assign(:deployment_channel, deployment_channel)
      |> assign(:reference_id, ref_id)

    {:noreply, socket}
  end

  # We can save a fairly expensive query by checking the incoming deployment's payload
  # If it matches, we can set the deployment directly and only do 3 queries (update, two preloads)
  def handle_info(
        %Broadcast{event: "deployments/changed", topic: "deployment:none", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    if device_matches_deployment_payload?(device, payload) do
      {:noreply, assign_deployment(socket, payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %Broadcast{event: "deployments/changed", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    if device_matches_deployment_payload?(device, payload) do
      :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})
      {:noreply, assign_deployment(socket, payload)}
    else
      # jitter over a minute but spaced out to attempt to not
      # slam the database when all devices check
      jitter = :rand.uniform(30) * 2 * 1000
      Process.send_after(self(), :resolve_changed_deployment, jitter)
      {:noreply, socket}
    end
  end

  def handle_info(:resolve_changed_deployment, %{assigns: %{device: device}} = socket) do
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
      socket.assigns.reference_id
    )

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    {:noreply, update_device(socket, device)}
  end

  # manually pushed
  def handle_info(
        %Broadcast{event: "deployments/update", payload: %{deployment_id: nil} = payload},
        socket
      ) do
    :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})
    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  def handle_info({"deployments/update", inflight_update}, %{assigns: %{device: device}} = socket) do
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
          socket.assigns.reference_id
        )

        Devices.update_started!(inflight_update)
        push(socket, "update", payload)

        {:noreply, socket}

      false ->
        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "moved"}, socket) do
    # The old deployment is no longer valid, so let's look one up again
    handle_info(:resolve_changed_deployment, socket)
  end

  # Update local state and tell the various servers of the new information
  def handle_info(%Broadcast{event: "devices/updated"}, %{assigns: %{device: device}} = socket) do
    device = Repo.reload(device)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.merge(value, %{
        updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device)
      })
    end)

    socket =
      socket
      |> update_device(device)
      |> maybe_start_penalty_timer()

    {:noreply, socket}
  end

  def handle_info(:online?, socket) do
    NervesHub.Tracker.online(socket.assigns.device)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    # Forward broadcasts to the device for now
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(:penalty_box_check, %{assigns: %{device: device}} = socket) do
    updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)

    :telemetry.execute([:nerves_hub, :devices, :penalty_box, :check], %{
      updates_enabled: updates_enabled
    })

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.merge(value, %{updates_enabled: updates_enabled})
    end)

    # Just in case time is weird or it got placed back in between checks
    socket =
      if !updates_enabled do
        maybe_start_penalty_timer(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:push, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    # Ignore unhandled messages so that it doesn't crash the link process
    # preventing cascading problems.
    Logger.warning("[DeviceChannel] Unhandled message! - #{inspect(msg)}")

    _ =
      Sentry.capture_message("[DeviceChannel] Unhandled message!",
        extra: %{message: msg},
        result: :none
      )

    {:noreply, socket}
  end

  def handle_in("fwup_progress", %{"value" => percent}, %{assigns: %{device: device}} = socket) do
    NervesHubWeb.DeviceEndpoint.broadcast_from!(
      self(),
      "device:#{device.identifier}:internal",
      "fwup_progress",
      %{
        percent: percent
      }
    )

    # if this is the first fwup we see, then mark it as an update attempt
    socket =
      if !socket.assigns.update_started? do
        # reload update attempts because they might have been cleared
        # and we have a cached stale version
        updated_device = Repo.reload(device)
        device = %{device | update_attempts: updated_device.update_attempts}

        {:ok, device} = Devices.update_attempted(device)

        Registry.update_value(NervesHub.Devices, device.id, fn value ->
          Map.put(value, :updating, true)
        end)

        socket
        |> assign(:device, device)
        |> assign(:update_started?, true)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_in("connection_types", %{"values" => types}, %{assigns: %{device: device}} = socket) do
    {:ok, device} = Devices.update_device(device, %{"connection_types" => types})
    {:noreply, assign(socket, :device, device)}
  end

  def handle_in("status_update", %{"status" => _status}, socket) do
    # TODO store in tracker or the database?
    {:noreply, socket}
  end

  def handle_call("rebooting", _, socket) do
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1})

    {:ok, device} =
      Devices.update_device(socket.assigns.device, %{last_communication: DateTime.utc_now()})

    description = "device #{device.identifier} disconnected from the server"

    AuditLogs.audit_with_ref!(device, device, description, socket.assigns.reference_id)

    Registry.unregister(NervesHub.Devices, device.id)
    Tracker.offline(device)

    :ok
  end

  defp subscribe(topic) do
    Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
  end

  defp unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
  end

  # The reported firmware is the same as what we already know about
  defp update_metadata(%Device{firmware_metadata: %{uuid: uuid}} = device, %{
         "nerves_fw_uuid" => uuid
       }) do
    {:ok, device}
  end

  # A new UUID is being reported from an update
  defp update_metadata(device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params),
         {:ok, device} <- Devices.update_firmware_metadata(device, metadata) do
      Devices.firmware_update_successful(device)
    end
  end

  defp maybe_start_penalty_timer(%{assigns: %{device: %{updates_blocked_until: nil}}} = socket),
    do: socket

  defp maybe_start_penalty_timer(socket) do
    check_penalty_box_in =
      DateTime.diff(socket.assigns.device.updates_blocked_until, DateTime.utc_now(), :millisecond)

    ref =
      if check_penalty_box_in > 0 do
        _ =
          if socket.assigns.penalty_timer, do: Process.cancel_timer(socket.assigns.penalty_timer)

        # delay the check slightly to make sure the penalty is cleared when its updated
        Process.send_after(self(), :penalty_box_check, check_penalty_box_in + 1000)
      end

    assign(socket, :penalty_timer, ref)
  end

  defp device_matches_deployment_payload?(device, payload) do
    payload.active &&
      device.product_id == payload.product_id &&
      device.firmware_metadata.platform == payload.platform &&
      device.firmware_metadata.architecture == payload.architecture &&
      Enum.all?(payload.conditions["tags"], &Enum.member?(device.tags, &1)) &&
      Deployments.version_match?(device, payload)
  end

  defp assign_deployment(%{assigns: %{device: device}} = socket, payload) do
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, payload.id)
      |> Repo.update!()
      |> Repo.preload([deployment: [:firmware]], force: true)

    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit_with_ref!(device, device, description, socket.assigns.reference_id)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    update_device(socket, device)
  end

  def update_device(socket, device) do
    unsubscribe(socket.assigns.deployment_channel)

    deployment_channel =
      if device.deployment_id do
        "deployment:#{device.deployment_id}"
      else
        "deployment:none"
      end

    subscribe(deployment_channel)

    socket
    |> assign(:device, device)
    |> assign(:deployment_channel, deployment_channel)
  end

  defp push(event, payload) do
    send(self(), {:push, event, payload})
  end
end
