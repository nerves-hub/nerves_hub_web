defmodule NervesHubWeb.FeaturesChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias NervesHub.Devices

  @impl Phoenix.Channel
  def join("features", payload, socket) do
    attach_list =
      for {feature, ver} <- payload, into: %{} do
        {feature, allowed?(feature, ver)}
      end

    topic = "device:#{socket.assigns.device.id}:features"
    NervesHubWeb.DeviceEndpoint.subscribe(topic)

    {:ok, attach_list, socket}
  end

  defp allowed?(_feature, _ver) do
    # TODO: Some conditions for allow/disallow feature
    true
  end

  @impl Phoenix.Channel
  def handle_in("geo:location:update", location, %{assigns: %{device: device}} = socket) do
    metadata = Map.put(device.connection_metadata, "location", location)

    {:ok, device} = Devices.update_device(device, %{connection_metadata: metadata})

    _ =
      NervesHubWeb.DeviceEndpoint.broadcast(
        "device:#{device.identifier}:internal",
        "location:updated",
        location
      )

    {:noreply, assign(socket, :device, device)}
  end

  def handle_in(event, payload, socket) do
    dbg({event, payload})
    {:noreply, socket}
  end

  @impl Phoenix.Channel
  # TODO: Get specific on messages passed to device
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
