# Channel the device is connected to
defmodule NervesHubWeb.ConsoleChannel do
  use Phoenix.Channel

  alias NervesHub.Devices
  alias NervesHub.Repo
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

  def handle_info({:after_join, _payload}, socket) do
    socket.endpoint.subscribe(console_topic(socket))

    # now that the console is connected, push down the device's elixir, line by line
    device = socket.assigns.device
    device = Repo.preload(device, [:deployment])
    deployment = device.deployment

    if deployment && deployment.connecting_code do
      device.deployment.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        push(socket, "dn", %{"data" => character})
      end)

      push(socket, "dn", %{"data" => "\r"})
    end

    if device.connecting_code do
      device.connecting_code
      |> String.graphemes()
      |> Enum.map(fn character ->
        push(socket, "dn", %{"data" => character})
      end)

      push(socket, "dn", %{"data" => "\r"})
    end

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
