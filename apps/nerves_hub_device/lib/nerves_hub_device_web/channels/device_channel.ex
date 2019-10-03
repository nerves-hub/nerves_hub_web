defmodule NervesHubDeviceWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently join a `Phoenix.Presence` topic scoped by organization.
  """

  use NervesHubDeviceWeb, :channel

  alias NervesHubWebCore.{
    AuditLogs,
    Deployments.Deployment,
    Devices,
    Devices.Device,
    Firmwares,
    Repo
  }

  alias NervesHubDevice.Presence

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
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "device:#{device.id}")
      deployments = Devices.get_eligible_deployments(device)
      join_reply = Devices.resolve_update(device, deployments)

      if join_reply.update_available do
        AuditLogs.audit!(hd(deployments), device, :update, %{
          from: "channel_join",
          send_update_message: true
        })
      end

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
    Presence.update(
      socket.channel_pid,
      "product:#{socket.assigns.device.product_id}:devices",
      socket.assigns.device.id,
      %{fwup_progress: percent}
    )

    {:noreply, socket}
  end

  def handle_in("status_update", %{"status" => status}, socket) do
    Presence.update(
      socket.channel_pid,
      "product:#{socket.assigns.device.product_id}:devices",
      socket.assigns.device.id,
      %{status: status}
    )

    {:noreply, socket}
  end

  def handle_in("rebooting", _payload, socket) do
    # Device sends "rebooting" message back to signify ack of the request
    Presence.update(
      socket.channel_pid,
      "product:#{socket.assigns.device.product_id}:devices",
      socket.assigns.device.id,
      %{rebooting: true}
    )

    {:noreply, socket}
  end

  def handle_info({:after_join, device, update_available}, socket) do
    %Device{id: device_id, firmware_metadata: firmware_metadata, product_id: product_id} = device

    {:ok, _} =
      Presence.track(
        socket.channel_pid,
        "product:#{product_id}:devices",
        device_id,
        %{
          connected_at: System.system_time(:second),
          last_communication: device.last_communication,
          update_available: update_available,
          firmware_metadata: firmware_metadata
        }
      )

    {:noreply, socket}
  end

  def handle_info(%{payload: payload, event: "update"}, socket) do
    {deployment, payload} =
      Map.pop_lazy(payload, :deployment, fn -> Repo.get(Deployment, payload.deployment_id) end)

    # If we get here, the device is connected and high probability it receives
    # the update message so we can Audit and later assert on this audit event
    # as a loosely valid attempt to update
    AuditLogs.audit!(deployment, socket.assigns.device, :update, %{
      from: "broadcast",
      send_update_message: true
    })

    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info(%{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_out("presence_diff", _msg, socket) do
    {:noreply, socket}
  end

  def terminate(_reason, %{assigns: %{device: device}}) do
    if device = Devices.get_device(device.id) do
      Devices.update_device(device, %{last_communication: DateTime.utc_now()})
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp get_certificate(%{assigns: %{certificate: certificate}}), do: {:ok, certificate}

  defp get_certificate(_), do: {:error, :no_device_or_org}

  def update_metadata(%Device{firmware_metadata: %{uuid: uuid}} = device, %{
        "nerves_fw_uuid" => uuid
      }) do
    {:ok, device}
  end

  def update_metadata(device, params) do
    with {:ok, metadata} <- Firmwares.metadata_from_device(params) do
      Devices.update_firmware_metadata(device, metadata)
    end
  end
end
