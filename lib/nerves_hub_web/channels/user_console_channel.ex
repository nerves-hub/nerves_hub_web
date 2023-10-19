defmodule NervesHubWeb.UserConsoleChannel do
  use NervesHubWeb, :channel

  alias Phoenix.Socket.Broadcast

  def join("user:console:" <> device_id, _, socket) do
    topic = "device:console:#{device_id}"
    Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, {:connect, self()})
    {:ok, assign(socket, :device_id, device_id)}
  end

  def handle_in("message", payload, socket) do
    payload = Map.put(payload, :username, socket.assigns.user.username)
    broadcast(socket, "message", payload)
    {:noreply, socket}
  end

  def handle_in("file-data/start", payload, socket) do
    topic = "device:console:#{socket.assigns.device_id}"
    socket.endpoint.broadcast!(topic, "file-data/start", payload)
    {:noreply, socket}
  end

  def handle_in("file-data", payload, socket) do
    topic = "device:console:#{socket.assigns.device_id}"
    socket.endpoint.broadcast!(topic, "file-data", payload)
    {:noreply, socket}
  end

  def handle_in("file-data/stop", payload, socket) do
    topic = "device:console:#{socket.assigns.device_id}"
    socket.endpoint.broadcast!(topic, "file-data/stop", payload)
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    # Keypresses are coming in here raw
    # Send them to the device
    topic = "device:console:#{socket.assigns.device_id}"
    socket.endpoint.broadcast!(topic, event, payload)
    {:noreply, socket}
  end

  def handle_info({:metadata, metadata}, socket) do
    push(socket, "metadata", metadata)
    {:noreply, assign(socket, :metadata, metadata)}
  end

  def handle_info({:cache, lines}, socket) do
    push(socket, "up", %{data: lines})
    {:noreply, socket}
  end

  # This ties in the messages from Device that need to be handled in the console
  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    broadcast(socket, "message", %{
      username: socket.assigns.user.username,
      event: "closed the console"
    })

    socket
  end
end
