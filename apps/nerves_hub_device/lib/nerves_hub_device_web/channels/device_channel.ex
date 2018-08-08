defmodule NervesHubDeviceWeb.DeviceChannel do
  use NervesHubDeviceWeb, :channel

  alias NervesHubCore.{Devices, Firmwares, Accounts, Deployments}
  alias NervesHubDevice.Presence

  @uploader Application.get_env(:nerves_hub_www, :firmware_upload)

  def join("device:" <> serial, payload, socket) do
    if authorized?(socket, serial) do
      with {:ok, message} <- build_message(socket, payload) do
        send(self(), {:after_join, message})
        {:ok, message, socket}
      else
        {:error, reply} -> {:error, reply}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_info({:after_join, %{update_available: update_available} = message}, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.device.identifier, %{
        connected_at: inspect(System.system_time(:seconds)),
        update_available: update_available
      })

    {:noreply, socket}
  end

  defp build_message(%{assigns: %{device: device, org: org}}, payload) do
    with {:ok, device} <- device_update(device, org, payload) do
      send_update_message(device, org)
    else
      {:error, message} -> {:error, %{reason: message}}
      _ -> {:error, %{reason: :unknown_error}}
    end
  end

  defp build_message(_, _) do
    {:error, %{reason: :no_device_or_org}}
  end

  defp device_update(%Devices.Device{} = device, %Accounts.Org{} = org, %{
         "uuid" => uuid
       }) do
    with {:ok, firmware} <- Firmwares.get_firmware_by_uuid(org, uuid) do
      Devices.update_device(device, %{last_known_firmware_id: firmware.id})
    else
      _ -> {:error, :no_firmware_found}
    end
  end

  defp device_update(_, _, _), do: {:error, :no_firmware_uuid}

  defp send_update_message(%Devices.Device{} = device, org) do
    device
    |> Devices.get_eligible_deployments()
    |> do_update_message(org)
  end

  defp do_update_message([%Deployments.Deployment{} = deployment | _], org) do
    with {:ok, firmware} <- Firmwares.get_firmware(org, deployment.firmware_id),
         {:ok, url} <- @uploader.download_file(firmware) do
      {:ok, %{update_available: true, firmware_url: url}}
    else
      _ -> {:error, :no_firmware_url}
    end
  end

  defp do_update_message([], _) do
    {:ok, %{update_available: false}}
  end

  defp do_update_message(_, _), do: {:error, :unknown_error}

  def online?(%Devices.Device{} = device) do
    "device:#{device.identifier}"
    |> Presence.list()
    |> Map.has_key?(device.identifier)
  end

  def update_pending?(%Devices.Device{} = device) do
    "device:#{device.identifier}"
    |> Presence.list()
    |> Map.get(device.identifier, %{})
    |> Map.get(:metas, [%{}])
    |> List.first()
    |> Map.get(:update_available, false)
  end

  # Add authorization logic here as required.
  defp authorized?(%{assigns: %{device: %Devices.Device{identifier: identifier}}}, identifier) do
    true
  end

  defp authorized?(_, _) do
    false
  end
end
