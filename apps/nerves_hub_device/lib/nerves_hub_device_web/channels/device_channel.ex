defmodule NervesHubDeviceWeb.DeviceChannel do
  @moduledoc """
  The channel over which firmware updates are communicated to devices.

  After joining, devices will subsequently join a `Phoenix.Presence` topic scoped by organization.
  """

  use NervesHubDeviceWeb, :channel
  alias NervesHubCore.{Accounts.Org, Devices, Devices.Device, Firmwares, Deployments}
  alias NervesHubDevice.Presence

  @uploader Application.get_env(:nerves_hub_core, :firmware_upload)

  intercept(["presence_diff"])

  def join("firmware:" <> fw_uuid, _payload, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate),
         {:ok, device} <- Devices.update_last_known_firmware(device, fw_uuid) do
      deployments = Devices.get_eligible_deployments(device)
      join_reply = resolve_update(device.org, deployments)
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

  defp resolve_update(_org, _deployments = []), do: %{update_available: false}

  defp resolve_update(org, [%Deployments.Deployment{} = deployment | _]) do
    with {:ok, firmware} <- Firmwares.get_firmware(org, deployment.firmware_id),
         {:ok, url} <- @uploader.download_file(firmware) do
      %{update_available: true, firmware_url: url}
    else
      _ -> %{update_available: false}
    end
  end

  defp get_certificate(%{assigns: %{certificate: certificate}}), do: {:ok, certificate}

  defp get_certificate(_), do: {:error, :no_device_or_org}
end
