defmodule NervesHubWeb.DeviceChannel do
  use NervesHubWeb, :channel
  alias NervesHub.Devices

  def join("device:" <> serial, payload, socket) do
    if authorized?(socket, serial) do
      with {:ok, message} <- build_message(serial, payload) do
        {:ok, message, socket}
      else
        {:error, reply} -> {:error, reply}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp build_message(serial, payload) do
    with {:ok, device} <- db_operations(serial, payload) do
      {:ok, %{}}
      |> update_message(device, device.current_version)
    else
      {:error, message} -> {:error, %{reason: message}}
      _ -> {:error, %{reason: :unknown_error}}
    end
  end

  defp db_operations(serial, payload) do
    serial_check(serial)
    |> device_update(payload)
  end

  defp serial_check(serial) do
    with {:ok, device} <- Devices.get_device_by_identifier(serial) do
      {:ok, device}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp device_update({:error, message}, _), do: {:error, message}

  defp device_update({:ok, device}, %{"version" => version}) do
    Devices.update_device(device, %{current_version: version})
  end

  defp device_update(_, _), do: {:error, :no_firmware_version}

  defp update_message({:ok, %{} = message}, %Devices.Device{target_version: version}, version) do
    {:ok, %{update_available: false} |> Map.merge(message)}
  end

  defp update_message({:ok, %{} = message}, _, _) do
    {:ok, %{update_available: true} |> Map.merge(message)}
  end

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
  defp authorized?(%{assigns: %{serial: socket_serial}}, socket_serial) do
    true
  end

  defp authorized?(_, _) do
    false
  end
end
