defmodule NervesHubDeviceWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently join a `Phoenix.Presence` topic scoped by organization.
  """

  use NervesHubDeviceWeb, :channel
  alias NervesHubWebCore.{Accounts.Org, Devices, Devices.Device}
  alias NervesHubDevice.Presence

  intercept(["presence_diff"])

  def join("firmware:" <> fw_uuid, _payload, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate),
         {:ok, device} <- Devices.update_last_known_firmware(device, fw_uuid),
         {:ok, device} <- Devices.received_communication(device) do
      deployments = Devices.get_eligible_deployments(device)
      join_reply = Devices.resolve_update(device.org, deployments)
      Phoenix.PubSub.subscribe(NervesHubWeb.PubSub, "device:#{device.id}")
      send(self(), {:after_join, device, join_reply.update_available})
      {:ok, join_reply, socket}
    else
      {:error, _} = err -> err
    end
  end

  def handle_info({:after_join, device, update_available}, socket) do
    %Device{id: device_id, last_known_firmware_id: firmware_id, org: %Org{id: org_id}} = device

    {:ok, _} =
      Presence.track(
        socket.channel_pid,
        "devices:#{org_id}",
        device_id,
        %{
          connected_at: inspect(System.system_time(:seconds)),
          update_available: update_available,
          last_known_firmware_id: firmware_id
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
end
