defmodule NervesHubDeviceWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently join a `Phoenix.Presence` topic scoped by organization.
  """

  use NervesHubDeviceWeb, :channel
  alias NervesHubWebCore.{Accounts.Org, Devices, Devices.Device, Firmwares}
  alias NervesHubDevice.Presence

  intercept(["presence_diff"])

  def join("firmware:" <> fw_uuid, params, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate),
         params <- Map.put_new(params, "nerves_fw_uuid", fw_uuid),
         {:ok, device} <- update_metadata(device, params),
         {:ok, device} <- Devices.received_communication(device) do
      deployments = Devices.get_eligible_deployments(device)
      join_reply = Devices.resolve_update(device.org, deployments)
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "device:#{device.id}")
      send(self(), {:after_join, device, join_reply.update_available})
      {:ok, join_reply, socket}
    end
  end

  def handle_info({:after_join, device, update_available}, socket) do
    %Device{id: device_id, firmware_metadata: firmware_metadata, org: %Org{id: org_id}} = device

    {:ok, _} =
      Presence.track(
        socket.channel_pid,
        "devices:#{org_id}",
        device_id,
        %{
          connected_at: System.system_time(:second),
          update_available: update_available,
          firmware_metadata: firmware_metadata
        }
      )

    {:noreply, socket}
  end

  def handle_info(
        %{payload: %{device_id: device_id} = payload, event: event},
        %{assigns: %{certificate: %{device_id: device_id}}} = socket
      ) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_out("presence_diff", _msg, socket) do
    {:noreply, socket}
  end

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
