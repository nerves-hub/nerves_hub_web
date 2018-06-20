defmodule NervesHubWeb.DeviceChannel do
  use NervesHubWeb, :channel
  alias NervesHub.Devices
  alias NervesHub.Firmwares
  alias NervesHub.Accounts

  @uploader Application.get_env(:nerves_hub, :firmware_upload)

  def join("device:" <> serial, payload, socket) do
    if authorized?(socket, serial) do
      with {:ok, message} <- build_message(socket, payload) do
        {:ok, message, socket}
      else
        {:error, reply} -> {:error, reply}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp build_message(%{assigns: %{device: device, tenant: tenant}}, payload) do
    with {:ok, device} <- device_update(device, tenant, payload) do
      {:ok, %{}}
      |> update_message(device, tenant)
    else
      {:error, message} -> {:error, %{reason: message}}
      _ -> {:error, %{reason: :unknown_error}}
    end
  end

  defp build_message(_, _) do
    {:error, %{reason: :no_device_or_tenant}}
  end

  defp db_operations(serial, payload) do
    serial_check(serial)
    |> device_update(payload)
  end

  defp device_update(%Devices.Device{} = device, %Accounts.Tenant{} = tenant, %{
         "version" => version,
         "product" => product
       }) do
    with {:ok, firmware} <-
           Firmwares.get_firmware_by_product_and_version(
             tenant,
             product,
             version
           ) do
      Devices.update_device(device, %{current_firmware_id: firmware.id})
    else
      _ -> {:error, :no_firmware_found}
    end
  end

  defp device_update(_, _), do: {:error, :no_firmware_version}

  defp update_message(
         {:ok, %{} = message},
         %Devices.Device{
           target_deployment: %{firmware_id: firmware_id},
           current_firmware_id: firmware_id
         },
         _
       ) do
    {:ok, %{update_available: false} |> Map.merge(message)}
  end

  defp update_message(
         {:ok, %{} = message},
         %Devices.Device{target_deployment: %{firmware_id: firmware_id}},
         %Accounts.Tenant{} = tenant
       ) do
    with {:ok, firmware} <- Firmwares.get_firmware(tenant, firmware_id),
         {:ok, url} <- @uploader.download_file(firmware) do
      {:ok, %{update_available: true, firmware_url: url} |> Map.merge(message)}
    else
      _ -> {:error, :no_firmware_url}
    end
  end

  defp update_message(_, _), do: {:error, :unknown_error}

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (device:lobby).
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{assigns: %{device: %Devices.Device{identifier: identifier}}}, identifier) do
    true
  end

  defp authorized?(_, _) do
    false
  end
end
