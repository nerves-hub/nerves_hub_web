defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently track themselves for presence.
  """

  use Phoenix.Channel

  alias NervesHub.{
    AuditLogs,
    Deployments.Deployment,
    Devices,
    Devices.Device,
    Firmwares,
    Repo
  }

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
      socket.endpoint.subscribe("device:#{device.id}")
      deployments = Devices.get_eligible_deployments(device)

      join_reply =
        Devices.resolve_update(device, deployments)
        |> build_join_reply()

      if should_audit_log?(join_reply, params) do
        deployment = hd(deployments)

        description =
          "device #{device.identifier} received update for firmware #{deployment.firmware.version}(#{deployment.firmware.uuid}) via deployment #{deployment.name} after channel join"

        AuditLogs.audit!(deployment, device, :update, description, %{
          from: "channel_join",
          send_update_message: true
        })
      end

      send(self(), {:after_join, device, join_reply.update_available})
      {:ok, join_reply, assign(socket, :update_started?, false)}
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

  def handle_in("connection_types", %{"value" => types}, socket) do
    {:ok, device} = Devices.update_device(socket.assigns.device, %{"connection_types" => types})
    {:noreply, assign(socket, :device, device)}
  end

  def handle_info({:after_join, device, update_available}, socket) do
    Presence.track(
      device,
      %{
        product_id: device.product_id,
        connected_at: System.system_time(:second),
        last_communication: device.last_communication,
        update_available: update_available,
        firmware_metadata: device.firmware_metadata
      }
    )

    {:noreply, socket}
  end

  # manually pushed
  def handle_info(%Broadcast{event: "update", payload: %{deployment_id: nil} = payload}, socket) do
    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "update", payload: payload}, socket) do
    {deployment, payload} =
      Map.pop_lazy(payload, :deployment, fn -> Repo.get(Deployment, payload.deployment_id) end)

    device = socket.assigns.device

    description =
      "deployment #{deployment.name} update triggered device #{device.identifier} to update firmware #{deployment.firmware.uuid}"

    # If we get here, the device is connected and high probability it receives
    # the update message so we can Audit and later assert on this audit event
    # as a loosely valid attempt to update
    AuditLogs.audit!(deployment, device, :update, description, %{
      from: "broadcast",
      send_update_message: true
    })

    push(socket, "update", payload)

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "moved"}, socket) do
    device = Repo.reload(socket.assigns.device)
    Presence.update(device, %{product_id: device.product_id})

    {:noreply, assign(socket, device: device)}
  end

  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_info({:console, version}, socket) do
    metadata = %{console_available: true, console_version: version}
    # Update gproc and then also tell connected liveviews that the device changed
    Presence.update(socket.assigns.device, metadata)
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
end
