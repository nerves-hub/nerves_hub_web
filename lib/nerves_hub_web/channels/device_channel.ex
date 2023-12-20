defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication

  This is only the transport for which a device authenticates and connects
  when using websockets. For the Device interface, see NervesHub.Devices.DeviceLink
  """

  use Phoenix.Channel

  alias NervesHub.Devices.DeviceLink

  def join("device", params, %{assigns: %{device: device}} = socket) do
    socket_pid = self()

    push_cb = fn event, payload ->
      send(socket_pid, {:push, event, payload})
    end

    with {:ok, link} <-
           DeviceLink.connect(device, push_cb, params, monitor: socket.assigns.reference_id) do
      {:ok, assign(socket, :device_link_pid, link)}
    end
  end

  def handle_info({:push, event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  def handle_in(event, payload, socket) do
    DeviceLink.recv(socket.assigns.device_link_pid, event, payload)
    {:noreply, socket}
  end

  def terminate(_reason, _state), do: :ok
end
