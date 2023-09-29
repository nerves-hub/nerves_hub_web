defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently track themselves for presence.
  """

  use Phoenix.Channel

  alias NervesHub.AuditLogs
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceLink
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Tracker
  alias Phoenix.Socket.Broadcast

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def join("device", params, %{assigns: %{device: device}} = socket) do
    Tracer.with_span "DeviceChannel.join" do
      with {:ok, device} <- update_metadata(device, params),
           {:ok, device} <- Devices.device_connected(device) do
        Tracer.set_attribute("nerves_hub.device.id", device.id)
        Tracer.set_attribute("nerves_hub.device.identifier", device.identifier)

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
          |> Repo.preload(deployment: [:firmware])

        # clear out any inflight updates, there shouldn't be one at this point
        # we might make a new one right below it, so clear it beforehand
        Devices.clear_inflight_update(device)

        # Let the orchestrator handle this going forward
        join_reply =
          device
          |> Devices.resolve_update()
          |> build_join_reply()

        if should_audit_log?(join_reply, params) do
          deployment = device.deployment

          description =
            "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} after channel join"

          AuditLogs.audit_with_ref!(
            deployment,
            device,
            description,
            socket.assigns.reference_id
          )

          # if there's an update, track it
          Devices.told_to_update(device, deployment)
        end

        socket =
          socket
          |> assign(:update_started?, false)
          |> assign(:device, device)

        send(self(), {:after_join, device})

        {:ok, join_reply, socket}
      end
    end
  end

  def handle_in("fwup_progress", %{"value" => percent}, socket) do
    device = socket.assigns.device

    socket.endpoint.broadcast("device:#{device.identifier}:internal", "fwup_progress", %{
      percent: percent
    })

    # if this is the first fwup we see in the channel, then mark it as an update attempt
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

  def handle_in("status_update", %{"status" => _status}, socket) do
    trace("DeviceChannel.status_update", socket.assigns.device, fn ->
      # TODO store in tracker or the database?
      {:noreply, socket}
    end)
  end

  def handle_in("rebooting", _payload, socket) do
    trace("DeviceChannel.rebooting", socket.assigns.device, fn ->
      {:noreply, socket}
    end)
  end

  def handle_in("connection_types", %{"value" => types}, socket) do
    trace("DeviceChannel.connection_types", socket.assigns.device, fn ->
      {:ok, device} = Devices.update_device(socket.assigns.device, %{"connection_types" => types})
      {:noreply, assign(socket, :device, device)}
    end)
  end

  def handle_info({:after_join, device}, socket) do
    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1})

    trace("DeviceChannel.after_join", socket.assigns.device, fn ->
      {:ok, pid} = Devices.Supervisor.start_device(device)
      DeviceLink.connect(pid, self())

      socket = assign(socket, :device_link_pid, pid)

      start_penalty_timer(device)

      # local node tracking
      Registry.register(NervesHub.Devices, device.id, %{
        deployment_id: device.deployment_id,
        firmware_uuid: device.firmware_metadata.uuid,
        updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device),
        updating: false
      })

      # Cluster tracking
      Tracker.online(device)

      {:noreply, socket}
    end)
  end

  # We can save a fairly expensive query by checking the incoming deployment's payload
  # If it matches, we can set the deployment directly and only do 3 queries (update, two preloads)
  def handle_info(
        %Broadcast{event: "deployments/changed", topic: "deployment:none", payload: payload},
        socket
      ) do
    trace("DeviceChannel.deployment_changed", socket.assigns.device, fn ->
      device = socket.assigns.device

      if device_matches_deployment_payload?(device, payload) do
        {:noreply, assign_deployment(socket, device, payload)}
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_info(%Broadcast{event: "deployments/changed", payload: payload}, socket) do
    trace("DeviceChannel.deployment_changed", socket.assigns.device, fn ->
      device = socket.assigns.device

      if device_matches_deployment_payload?(device, payload) do
        :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})
        {:noreply, assign_deployment(socket, device, payload)}
      else
        # jitter over a minute but spaced out to attempt to not
        # slam the database when all devices check
        jitter = :rand.uniform(30) * 2 * 1000
        Process.send_after(self(), :resolve_changed_deployment, jitter)
        {:noreply, socket}
      end
    end)
  end

  def handle_info(:resolve_changed_deployment, socket) do
    trace("DeviceChannel.resolve_changed_deployment", socket.assigns.device, fn ->
      :telemetry.execute([:nerves_hub, :devices, :deployment, :changed], %{count: 1})

      device =
        socket.assigns.device
        |> Repo.reload()
        |> Deployments.set_deployment()
        |> Repo.preload([deployment: [:firmware]], force: true)

      if device.deployment_id do
        description =
          "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

        AuditLogs.audit_with_ref!(
          device,
          device,
          description,
          socket.assigns.reference_id
        )
      else
        description =
          "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"

        AuditLogs.audit_with_ref!(
          device,
          device,
          description,
          socket.assigns.reference_id
        )
      end

      DeviceLink.update_device(socket.assigns.device_link_pid, device)

      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.put(value, :deployment_id, device.deployment_id)
      end)

      {:noreply, assign(socket, :device, device)}
    end)
  end

  # manually pushed
  def handle_info(
        %Broadcast{event: "deployments/update", payload: %{deployment_id: nil} = payload},
        socket
      ) do
    trace("DeviceChannel.deployments_update", socket.assigns.device, fn ->
      :telemetry.execute([:nerves_hub, :devices, :update, :manual], %{count: 1})
      Tracer.set_attribute("nerves_hub.deployment.manual", true)
      push(socket, "update", payload)
      {:noreply, socket}
    end)
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  def handle_info({"deployments/update", inflight_update}, socket) do
    trace("DeviceChannel.deployments_update", socket.assigns.device, fn ->
      :telemetry.execute([:nerves_hub, :devices, :update, :automatic], %{count: 1})

      device = Repo.preload(socket.assigns.device, [deployment: [:firmware]], force: true)

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
    end)
  end

  def handle_info(%Broadcast{event: "moved"}, socket) do
    trace("DeviceChannel.deployment_moved", socket.assigns.device, fn ->
      device = Repo.reload(socket.assigns.device)

      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.put(value, :deployment_id, device.deployment_id)
      end)

      DeviceLink.update_device(socket.assigns.device_link_pid, device)

      # The old deployment is no longer valid, so let's look one up again
      send(self(), :resolve_changed_deployment)

      {:noreply, assign(socket, device: device)}
    end)
  end

  # Update local state and tell the various servers of the new information
  def handle_info(%Broadcast{event: "devices/updated"}, socket) do
    trace("DeviceChannel.devices_updated", socket.assigns.device, fn ->
      device = Repo.reload(socket.assigns.device)

      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.merge(value, %{
          updates_enabled: device.updates_enabled && !Devices.device_in_penalty_box?(device)
        })
      end)

      DeviceLink.update_device(socket.assigns.device_link_pid, device)

      start_penalty_timer(device)

      {:noreply, assign(socket, :device, device)}
    end)
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info(:penalty_box_check, socket) do
    trace("DeviceChannel.penalty_box_check", socket.assigns.device, fn ->
      device = socket.assigns.device

      updates_enabled = device.updates_enabled && !Devices.device_in_penalty_box?(device)

      Tracer.set_attribute("nerves_hub.device.updates_enabled", updates_enabled)

      :telemetry.execute([:nerves_hub, :devices, :penalty_box, :check], %{
        updates_enabled: updates_enabled
      })

      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.merge(value, %{updates_enabled: updates_enabled})
      end)

      # Just in case time is weird or it got placed back in between checks
      if !updates_enabled do
        start_penalty_timer(device)
      end

      {:noreply, socket}
    end)
  end

  def terminate(_reason, %{assigns: %{device: device, reference_id: reference_id}}) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1})

    if device = Devices.get_device(device.id) do
      {:ok, device} = Devices.update_device(device, %{last_communication: DateTime.utc_now()})

      description = "device #{device.identifier} disconnected from the server"

      AuditLogs.audit_with_ref!(device, device, description, reference_id)

      Registry.unregister(NervesHub.Devices, device.id)
      Tracker.offline(device)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

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

  defp build_join_reply(%{update_available: false}) do
    # If update_available is false, firmware_url should be nil
    # and that will crash the device. So we need to abandon
    # %UpdatePayload{} struct here and return a single key
    # map as is currently expected by nerves_hub_link
    %{update_available: false}
  end

  defp build_join_reply(%{firmware_url: nil}) do
    # This shouldn't even be possible, but a nil firmware_url
    # will crash the device in a very destructive way
    # so put this here to be safe
    Logger.warning("Device has update available, but no firmware_url - Ignoring")
    %{update_available: false}
  end

  defp build_join_reply(up), do: up

  defp should_audit_log?(%{update_available: false}, _), do: false

  defp should_audit_log?(%{deployment: %{firmware: %{uuid: uuid}}}, %{
         "currently_downloading_uuid" => uuid
       }) do
    false
  end

  defp should_audit_log?(_join_reply, _params), do: true

  defp device_matches_deployment_payload?(device, payload) do
    payload.active &&
      device.product_id == payload.product_id &&
      device.firmware_metadata.platform == payload.platform &&
      device.firmware_metadata.architecture == payload.architecture &&
      Enum.all?(payload.conditions["tags"], &Enum.member?(device.tags, &1)) &&
      Deployments.version_match?(device, payload)
  end

  defp assign_deployment(socket, device, payload) do
    trace("DeviceChannel.assign_deployment", socket.assigns.device, fn ->
      device =
        device
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:deployment_id, payload.id)
        |> Repo.update!()
        |> Repo.preload([deployment: [:firmware]], force: true)

      description =
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

      AuditLogs.audit_with_ref!(device, device, description, socket.assigns.reference_id)

      DeviceLink.update_device(socket.assigns.device_link_pid, device)

      Registry.update_value(NervesHub.Devices, device.id, fn value ->
        Map.put(value, :deployment_id, device.deployment_id)
      end)

      socket
      |> assign(:device, device)
      |> assign(:deployment_channel, "deployment:#{device.deployment_id}")
    end)
  end

  @doc """
  Start a timer for penalty box checking only if time is in the future
  """
  def start_penalty_timer(%{updates_blocked_until: nil}), do: :ok

  def start_penalty_timer(device) do
    check_penalty_box_in =
      DateTime.diff(device.updates_blocked_until, DateTime.utc_now(), :millisecond)

    if check_penalty_box_in > 0 do
      # delay the check slightly to make sure the penalty is cleared when its updated
      Process.send_after(self(), :penalty_box_check, check_penalty_box_in + 1000)
    end
  end

  def trace(name, device, fun) do
    Tracer.with_span name do
      Tracer.set_attributes(%{
        "nerves_hub.device.id" => device.id,
        "nerves_hub.device.identifier" => device.identifier
      })

      fun.()
    end
  end
end
