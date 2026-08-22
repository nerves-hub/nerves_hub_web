# Channel the device is connected to
defmodule NervesHubWeb.ConsoleChannel do
  use Phoenix.Channel

  alias NervesHub.Devices.DeviceMessages
  alias Phoenix.Socket.Broadcast

  def join("console", payload, socket) do
    send(self(), {:after_join, payload})

    {:ok, assign(socket, %{current_line: "", buffer: CircularBuffer.new(1024)})}
  end

  def terminate(_, _socket) do
    {:shutdown, :closed}
  end

  def handle_in("up", payload, socket) do
    :ok = record(socket, :received, "up", payload)

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

    user_topic(socket)
    |> socket.endpoint.broadcast!("up", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/start", payload, socket) do
    :ok = record(socket, :received, "file-data/start", payload)

    user_topic(socket)
    |> socket.endpoint.broadcast!("file-data/start", payload)

    {:noreply, socket}
  end

  def handle_in("file-data", payload, socket) do
    :ok = record(socket, :received, "file-data", payload)

    user_topic(socket)
    |> socket.endpoint.broadcast!("file-data", payload)

    {:noreply, socket}
  end

  def handle_in("file-data/stop", payload, socket) do
    :ok = record(socket, :received, "file-data/stop", payload)

    user_topic(socket)
    |> socket.endpoint.broadcast!("file-data/stop", payload)

    {:noreply, socket}
  end

  def handle_info({:after_join, payload}, socket) do
    socket = assign(socket, :version, payload["console_version"])

    # all devices are lumped into a `console` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    socket.endpoint.unsubscribe("console")

    socket.endpoint.subscribe(device_topic(socket))

    socket.endpoint.broadcast!(
      device_internal_topic(socket),
      "console_joined",
      %{}
    )

    {:noreply, socket}
  end

  def handle_info({:connect, pid}, socket) do
    metadata = %{version: socket.assigns.version}
    send(pid, {:metadata, metadata})

    lines = Enum.join(socket.assigns.buffer) <> socket.assigns.current_line
    send(pid, {:cache, lines})

    {:noreply, socket}
  end

  def handle_info({:active?, pid}, socket) do
    send(pid, :active)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    :ok = record(socket, :sent, event, payload)

    push(socket, event, payload)
    {:noreply, socket}
  end

  # Console traffic is recorded by size only, never by content — it is raw
  # terminal I/O, so its contents are whatever was typed at a prompt.
  # See `NervesHub.Devices.DeviceMessages`.
  defp record(socket, direction, event, payload) do
    DeviceMessages.record_size_only(socket.assigns.device_info, direction, :console, event, payload)
  end

  defp device_topic(socket), do: "device:console:#{socket.assigns.device_info.device_id}"

  defp device_internal_topic(socket), do: "device:console:#{socket.assigns.device_info.device_id}:internal"

  defp user_topic(socket), do: "user:console:#{socket.assigns.device_info.device_id}"
end
