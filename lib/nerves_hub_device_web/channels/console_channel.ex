# Channel the device is connected to
defmodule NervesHubDeviceWeb.ConsoleChannel do
  use Phoenix.Channel

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.Devices
  alias Phoenix.Socket.Broadcast

  def join("console", payload, socket) do
    with {:ok, certificate} <- get_certificate(socket),
         {:ok, device} <- Devices.get_device_by_certificate(certificate) do
      send(self(), {:after_join, payload})
      {:ok, assign(socket, :device, device)}
    else
      {:error, _} = err -> err
    end
  end

  def terminate(_, _socket) do
    {:shutdown, :closed}
  end

  def handle_in("init_attempt", %{"success" => success?} = payload, socket) do
    unless success? do
      socket.endpoint.broadcast_from(self(), console_topic(socket), "init_failure", payload)
    end

    {:noreply, socket}
  end

  def handle_in("put_chars", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "put_chars", payload)
    {:reply, :ok, socket}
  end

  def handle_in("get_line", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "get_line", payload)
    {:noreply, socket}
  end

  def handle_in("up", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "up", payload)
    {:noreply, socket}
  end

  def handle_info({:after_join, payload}, socket) do
    socket.endpoint.subscribe(console_topic(socket))
    version = Map.get(payload, "console_version", "0.1.0")

    {pid, _value} = Presence.await(socket.assigns.device)
    send(pid, {:console, version})

    {:noreply, socket}
  end

  def handle_info(%{event: "phx_leave"}, socket) do
    {:noreply, socket}
  end

  # This broadcasted message is meant for other LiveView windows
  def handle_info(%Broadcast{event: "add_line"}, socket) do
    {:noreply, socket}
  end

  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp console_topic(%{assigns: %{device: device}}) do
    "console:#{device.id}"
  end

  defp get_certificate(%{assigns: %{certificate: certificate}}), do: {:ok, certificate}

  defp get_certificate(_), do: {:error, :no_device_or_org}
end
