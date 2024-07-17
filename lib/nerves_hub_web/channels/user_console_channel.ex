defmodule NervesHubWeb.UserConsoleChannel do
  use NervesHubWeb, :channel

  alias NervesHub.Accounts
  alias NervesHub.Helpers.Authorization
  alias Phoenix.Socket.Broadcast

  def join("user:console:" <> device_id, _, socket) do
    if authorized?(socket.assigns.user, device_id) do
      topic = "device:console:#{device_id}"
      _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, topic, {:connect, self()})
      {:ok, assign(socket, :device_id, device_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("message", payload, socket) do
    payload = Map.put(payload, :name, socket.assigns.user.name)
    _ = broadcast(socket, "message", payload)
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
    _ =
      broadcast(socket, "message", %{
        name: socket.assigns.user.name,
        event: "closed the console"
      })

    socket
  end

  defp authorized?(user, device_id) do
    case Accounts.find_org_user_with_device(user, device_id) do
      nil ->
        false

      org_user ->
        Authorization.authorized?(:"device:console", org_user)
    end
  end
end
