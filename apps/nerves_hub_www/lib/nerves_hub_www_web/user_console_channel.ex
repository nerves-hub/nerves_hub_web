defmodule NervesHubWWWWeb.UserConsoleChannel do
  use NervesHubWWWWeb, :channel

  alias Phoenix.Socket.Broadcast

  # intercept(["presence_diff"])

  def join("user_console", %{"device_id" => device_id, "product_id" => product_id}, socket) do
    socket.endpoint.subscribe(console_topic(device_id))
    socket.endpoint.subscribe("product:#{product_id}:devices")
    {:ok, assign(socket, :device_id, device_id)}
  end

  def handle_in(event, payload, %{assigns: %{device_id: device_id}} = socket) do
    # Keypresses are coming in here raw
    # Send them to the device
    socket.endpoint.broadcast_from!(self(), console_topic(device_id), event, payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{payload: payload, event: "presence_diff"}, socket) do
    cond do
      meta = payload.joins[socket.assigns.device_id] ->
        push(socket, "meta_update", meta)

      payload.leaves[socket.assigns.device_id] ->
        # We're counting a device leaving as its last_communication. This is
        # slightly inaccurate to set here, but only by a minuscule amount
        # and saves DB calls and broadcasts
        disconnect_time = DateTime.truncate(DateTime.utc_now(), :second)

        meta = %{
          console_available: false,
          fwup_progress: nil,
          last_communication: disconnect_time,
          status: "offline"
        }

        push(socket, "meta_update", meta)

      # happens when a device leaves or joins but not the device this particular
      # process is concerned with
      true ->
        :noop
    end

    {:noreply, socket}
  end

  # This ties in the messages from Device that need to be handled in the console
  def handle_info(%Broadcast{payload: payload, event: event}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp console_topic(device_id) do
    "console:#{device_id}"
  end
end
