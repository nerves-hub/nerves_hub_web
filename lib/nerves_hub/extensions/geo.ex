defmodule NervesHub.Extensions.Geo do
  @behaviour NervesHub.Extensions

  alias NervesHub.Devices.Connections
  alias Phoenix.Channel.Server

  @impl NervesHub.Extensions
  def description() do
    """
    Reporting of GeoIP information or custom geo-location information sources
    you've set up for your device.
    """
  end

  @impl NervesHub.Extensions
  def enabled?() do
    true
  end

  @impl NervesHub.Extensions
  def attach(socket) do
    extension_config = Application.get_env(:nerves_hub, :extension_config)
    geo_interval = get_in(extension_config, [:geo, :interval_minutes]) || 0

    send(self(), {__MODULE__, :location_request})

    socket =
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

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def detach(socket) do
    _ = if socket.assigns[:geo_timer], do: :timer.cancel(socket.assigns.geo_timer)
    {:noreply, Phoenix.Socket.assign(socket, :geo_timer, nil)}
  end

  @impl NervesHub.Extensions
  def handle_in("location:update", location, socket) do
    Connections.merge_update_metadata(socket.assigns.reference_id, %{location: location})
    event = "location:updated"
    topic = "device:#{socket.assigns.device.identifier}:internal"
    _ = Server.broadcast(NervesHub.PubSub, topic, event, location)

    {:noreply, socket}
  end

  @impl NervesHub.Extensions
  def handle_info(:location_request, socket) do
    Phoenix.Channel.push(socket, "geo:location:request", %{})
    {:noreply, socket}
  end
end
