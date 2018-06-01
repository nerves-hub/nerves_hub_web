defmodule NervesHubWeb.DeviceChannel do
  use NervesHubWeb, :channel

  def join("device:" <> serial, _payload, socket) do
    if authorized?(socket, serial) do
      {:ok, %{serial: serial}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
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
