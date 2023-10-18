defmodule NervesHubWeb.UserConsoleChannel do
  use NervesHubWeb, :channel

  alias Phoenix.Socket.Broadcast

  def join("user:console:" <> device_id, _, socket) do
    Phoenix.PubSub.broadcast(NervesHub.PubSub, console_topic(device_id), {:connect, self()})
    socket.endpoint.subscribe(console_topic(device_id))
    {:ok, assign(socket, :device_id, device_id)}
  end

  def handle_in("message", payload, socket) do
    payload = Map.put(payload, :username, socket.assigns.user.username)
    broadcast(socket, "message", payload)
    {:noreply, socket}
  end

  def handle_in(event, payload, %{assigns: %{device_id: device_id}} = socket) do
    # Keypresses are coming in here raw
    # Send them to the device
    socket.endpoint.broadcast_from!(self(), console_topic(device_id), event, payload)
    {:noreply, socket}
  end

  # Ignore other connects
  def handle_info({:connect, _pid}, socket), do: {:noreply, socket}

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

  defp console_topic(device_id) do
    "console:#{device_id}"
  end
end
