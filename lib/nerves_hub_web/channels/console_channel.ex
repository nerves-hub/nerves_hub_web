# Channel the device is connected to
defmodule NervesHubWeb.ConsoleChannel do
  use Phoenix.Channel

  alias NervesHub.Repo
  alias Phoenix.Socket.Broadcast

  def join("console", payload, %{assigns: %{device: device}} = socket) do
    send(self(), {:after_join, payload})

    socket =
      socket
      |> assign(:device, device)
      |> assign(:current_line, "")
      |> assign(:buffer, CircularBuffer.new(1024))

    {:ok, socket}
  end

  def terminate(_, _socket) do
    {:shutdown, :closed}
  end

  def handle_in("up", payload, socket) do
    current_line = socket.assigns.current_line <> payload["data"]
    [current_line | lines] = Enum.reverse(String.split(current_line, "\n"))

    buffer =
      Enum.reduce(Enum.reverse(lines), socket.assigns.buffer, fn line, buffer ->
        CircularBuffer.insert(buffer, line <> "\n")
      end)

    socket =
      socket
      |> assign(:current_line, current_line)
      |> assign(:buffer, buffer)

    socket.endpoint.broadcast_from!(self(), console_topic(socket), "up", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/start", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "file-data/start", payload)
    {:noreply, socket}
  end

  def handle_in("file-data", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "file-data", payload)
    {:noreply, socket}
  end

  def handle_in("file-data/stop", payload, socket) do
    socket.endpoint.broadcast_from!(self(), console_topic(socket), "file-data/stop", payload)
    {:noreply, socket}
  end

  def handle_info({:after_join, payload}, socket) do
    socket = assign(socket, :version, payload["console_version"])

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

  def handle_info({:connect, pid}, socket) do
    metadata = %{version: socket.assigns.version}
    send(pid, {:metadata, metadata})

    lines = Enum.join(socket.assigns.buffer) <> socket.assigns.current_line
    send(pid, {:cache, lines})

    {:noreply, socket}
  end

  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp console_topic(%{assigns: %{device: device}}) do
    "console:#{device.id}"
  end
end
