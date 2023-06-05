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

  alias NervesHubDevice.Presence
  alias Phoenix.Socket.Broadcast

  require Logger

  intercept(["presence_diff"])

  def join("firmware:" <> fw_uuid, params, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate) do
      params = Map.put_new(params, "nerves_fw_uuid", fw_uuid)
      join("device", params, assign(socket, :device, device))
    end
  end

  def join("device", params, %{assigns: %{device: device}} = socket) do
    with {:ok, device} <- update_metadata(device, params),
         {:ok, device} <- Devices.device_connected(device) do
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

        AuditLogs.audit!(deployment, device, :update, description, %{from: "channel_join"})

        # if there's an update, track it
        Devices.told_to_update(device, deployment)
      end

      socket =
        socket
        |> assign(:update_started?, false)
        |> assign(:device, device)

      send(self(), {:after_join, device, join_reply.update_available})

      {:ok, join_reply, socket}
    end
  end

  def join("device", params, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate) do
      join("device", params, assign(socket, :device, device))
    end
  end

  def handle_in("fwup_progress", %{"value" => percent}, socket) do
    # No need to update the product channel which will spam anyone listening on
    # the listing of devices.
    Presence.update(socket.assigns.device, %{fwup_progress: percent}, product: false)

    # if this is the first fwup we see in the channel, then mark it as an update attempt
    socket =
      if !socket.assigns.update_started? do
        # reload update attempts because they might have been cleared
        # and we have a cached stale version
        device = socket.assigns.device
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

  def handle_in("status_update", %{"status" => status}, socket) do
    Presence.update(socket.assigns.device, %{status: status})

    {:noreply, socket}
  end

  def handle_in("rebooting", _payload, socket) do
    # Device sends "rebooting" message back to signify ack of the request
    Presence.update(socket.assigns.device, %{rebooting: true})

    {:noreply, socket}
  end

  def handle_in("reconnect", _payload, socket) do
    {:stop, :shutdown, socket}
  end

  def handle_in("connection_types", %{"value" => types}, socket) do
    {:ok, device} = Devices.update_device(socket.assigns.device, %{"connection_types" => types})
    {:noreply, assign(socket, :device, device)}
  end

  def handle_info({:after_join, device, update_available}, socket) do
    {:ok, pid} = Devices.Supervisor.start_device(device)
    DeviceLink.connect(pid, self())

    socket = assign(socket, :device_link_pid, pid)

    # local node tracking
    Registry.register(NervesHub.Devices, device.id, %{
      deployment_id: device.deployment_id,
      firmware_uuid: device.firmware_metadata.uuid,
      updating: false
    })

    # Cluster tracking
    Presence.track(device, %{
      product_id: device.product_id,
      deployment_id: device.deployment_id,
      connected_at: System.system_time(:second),
      last_communication: device.last_communication,
      update_available: update_available,
      firmware_metadata: device.firmware_metadata
    })

    {:noreply, socket}
  end

  # We can save a fairly expensive query by checking the incoming deployment's payload
  # If it matches, we can set the deployment directly and only do 3 queries (update, two preloads)
  def handle_info(
        %Broadcast{event: "deployments/changed", topic: "deployment:none", payload: payload},
        socket
      ) do
    device = socket.assigns.device

    Presence.update(device, %{
      deployment_id: nil
    })

    if device_matches_deployment_payload?(device, payload) do
      {:noreply, assign_deployment(socket, device, payload)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "deployments/changed", payload: payload}, socket) do
    device = socket.assigns.device

    if device_matches_deployment_payload?(device, payload) do
      {:noreply, assign_deployment(socket, device, payload)}
    else
      # jitter over a minute but spaced out to attempt to not
      # slam the database when all devices check
      jitter = :rand.uniform(30) * 2 * 1000
      Process.send_after(self(), :resolve_changed_deployment, jitter)
      {:noreply, socket}
    end
  end

  def handle_info(:resolve_changed_deployment, socket) do
    device =
      socket.assigns.device
      |> Repo.reload()
      |> Deployments.set_deployment()
      |> Repo.preload([deployment: [:firmware]], force: true)

    if device.deployment_id do
      description =
        "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

      AuditLogs.audit!(device, device, :update, description)
    else
      description =
        "device #{device.identifier} reloaded deployment and is no longer attached to a deployment"

      AuditLogs.audit!(device, device, :update, description)
    end

    DeviceLink.update_device(socket.assigns.device_link_pid, device)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    Presence.update(device, %{
      deployment_id: device.deployment_id
    })

    {:noreply, assign(socket, :device, device)}
  end

  # manually pushed
  def handle_info(
        %Broadcast{event: "deployments/update", payload: %{deployment_id: nil} = payload},
        socket
      ) do
    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "deployments/update"}, socket) do
    {:noreply, socket}
  end

  def handle_info({"deployments/update", inflight_update}, socket) do
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
        AuditLogs.audit!(deployment, device, :update, description, %{from: "broadcast"})

        Devices.update_started!(inflight_update)

        push(socket, "update", payload)

        {:noreply, socket}

      false ->
        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{event: "moved"}, socket) do
    device = Repo.reload(socket.assigns.device)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    Presence.update(device, %{
      product_id: device.product_id,
      deployment_id: device.deployment_id
    })

    # The old deployment is no longer valid, so let's look one up again
    send(self(), :resolve_changed_deployment)

    {:noreply, assign(socket, device: device)}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info({:console, version}, socket) do
    # Update gproc and then also tell connected liveviews that the device changed
    metadata = %{console_available: true, console_version: version}
    Presence.update(socket.assigns.device, metadata)

    # now that the console is connected, push down the device's elixir, line by line
    device = socket.assigns.device
    deployment = device.deployment

    if deployment && deployment.connecting_code do
      device.deployment.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        socket.endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{
          "data" => character
        })
      end)

      socket.endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{"data" => "\r"})
    end

    if device.connecting_code do
      device.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        socket.endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{
          "data" => character
        })
      end)

      socket.endpoint.broadcast_from!(self(), "console:#{device.id}", "dn", %{"data" => "\r"})
    end

    {:noreply, socket}
  end

  def handle_out("presence_diff", _msg, socket) do
    {:noreply, socket}
  end

  def terminate(_reason, %{assigns: %{device: device}}) do
    if device = Devices.get_device(device.id) do
      {:ok, device} = Devices.update_device(device, %{last_communication: DateTime.utc_now()})

      description = "device #{device.identifier} disconnected from the server"

      AuditLogs.audit!(device, device, :update, description, %{
        last_communication: device.last_communication,
        status: device.status
      })

      Registry.unregister(NervesHub.Devices, device.id)
      Presence.untrack(device)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp get_certificate(%{assigns: %{certificate: certificate}}), do: {:ok, certificate}

  defp get_certificate(_), do: {:error, :no_device_or_org}

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
    Logger.warn("Device has update available, but no firmware_url - Ignoring")
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
    device =
      device
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:deployment_id, payload.id)
      |> Repo.update!()
      |> Repo.preload([deployment: [:firmware]], force: true)

    description =
      "device #{device.identifier} reloaded deployment and is attached to deployment #{device.deployment.name}"

    AuditLogs.audit!(device, device, :update, description)

    DeviceLink.update_device(socket.assigns.device_link_pid, device)

    Registry.update_value(NervesHub.Devices, device.id, fn value ->
      Map.put(value, :deployment_id, device.deployment_id)
    end)

    Presence.update(device, %{
      deployment_id: device.deployment_id
    })

    socket
    |> assign(:device, device)
    |> assign(:deployment_channel, "deployment:#{device.deployment_id}")
  end
end
