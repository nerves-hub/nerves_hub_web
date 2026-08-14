# Channel the device is connected to
defmodule NervesHubWeb.ConsoleChannel do
  use Phoenix.Channel

  alias NervesHub.Consoles.PubSub
  alias Phoenix.Socket.Broadcast

  def join("console", payload, socket) do
    send(self(), {:after_join, payload})

    {:ok, assign(socket, %{current_line: "", buffer: CircularBuffer.new(1024)})}
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

    PubSub.broadcast_to_user_console(device_id(socket), "up", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/start", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data/start", payload)

    {:noreply, socket}
  end

  def handle_in("file-data", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/stop", payload, socket) do
    PubSub.broadcast_to_user_console(device_id(socket), "file-data/stop", payload)

    {:noreply, socket}
  end

  def handle_info({:after_join, payload}, socket) do
    socket = assign(socket, :version, payload["console_version"])

    # all devices are lumped into a `console` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    socket.endpoint.unsubscribe("console")

    PubSub.join_console(device_id(socket))

    PubSub.broadcast_console_joined(device_id(socket))

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

  defp device_id(socket), do: socket.assigns.device_info.device_id
end
