defmodule NervesHub.Features.Geo do
  @behaviour NervesHub.Features

  alias NervesHub.Devices

  @impl NervesHub.Features
  def attach(socket) do
    feature_config = Application.get_env(:nerves_hub, :feature_config)
    geo_interval = get_in(feature_config, [:geo, :interval_minutes]) || 0

    send(self(), {__MODULE__, :location_request})

    if geo_interval > 0 do
      timer =
        geo_interval
        |> :timer.minutes()
        |> :timer.send_interval({__MODULE__, :location_request})

      socket
      |> Phoenix.Socket.assign(:geo_timer, timer)
      |> Phoenix.Socket.assign(:geo_interval, geo_interval)
    else
      socket
    end
  end

  @impl NervesHub.Features
  def detach(socket) do
    _ = if socket.assigns[:geo_timer], do: :timer.cancel(socket.assigns.geo_timer)
    Phoenix.Socket.assign(socket, :geo_timer, nil)
  end

  @impl NervesHub.Features
  def handle_in("location:update", location, %{assigns: %{device: device}} = socket) do
    metadata = Map.put(device.connection_metadata, "location", location)

    {:ok, device} = Devices.update_device(device, %{connection_metadata: metadata})

    _ =
      NervesHubWeb.DeviceEndpoint.broadcast(
        "device:#{device.identifier}:internal",
        "location:updated",
        location
      )

    {:noreply, Phoenix.Socket.assign(socket, :device, device)}
  end

  @impl NervesHub.Features
  def handle_info(:location_request, socket) do
    Phoenix.Socket.push(socket, "geo:location:request", %{})
    {:noreply, socket}
  end
end
