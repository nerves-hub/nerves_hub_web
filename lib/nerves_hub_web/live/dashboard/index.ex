defmodule NervesHubWeb.Live.Dashboard.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  alias Phoenix.Socket.Broadcast

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    %{product: product} = socket.assigns

    socket
    |> page_title("Dashboard - #{product.name}")
    |> assign_devices_and_markers()
    |> subscribe_to_devices()
    |> start_refresh_cycle()
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_info(%Broadcast{event: "location:updated"}, socket) do
    socket
    |> assign_devices_and_markers()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:status"}, socket) do
    socket
    |> assign_devices_and_markers()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:change"}, socket) do
    socket
    |> assign_devices_and_markers()
    |> noreply()
  end

  def handle_info(:refresh_device_list, socket) do
    Process.send_after(self(), :refresh_device_list, 5000)

    socket
    |> assign_devices_and_markers()
    |> subscribe_to_devices()
    |> noreply()
  end

  defp start_refresh_cycle(socket) do
    Process.send_after(self(), :refresh_device_list, 5000)
    socket
  end

  defp subscribe_to_devices(socket) do
    if connected?(socket) do
      Enum.map(socket.assigns.devices, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")
      end)

      socket
    else
      socket
    end
  end

  defp assign_devices_and_markers(%{assigns: %{org: org, product: product}} = socket) do
    devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

    map_markers =
      Enum.reduce(devices, [], fn device, acc ->
        generate_map_marker(device, acc)
      end)

    socket
    |> assign(:devices, devices)
    |> assign(:map_markers, Jason.encode!(map_markers))
  end

  defp generate_map_marker(
         %Device{
           id: id,
           identifier: identifier,
           connection_status: connection_status,
           connection_metadata: %{"location" => location}
         },
         markers
       )
       when map_size(location) > 0 do
    new_marker =
      %{
        id: id,
        identifier: identifier,
        status: get_connection_status(connection_status),
        location: location
      }

    [new_marker | markers]
  end

  defp generate_map_marker(%Device{} = _device, markers) do
    markers
  end

  defp get_connection_status(:connected), do: "connected"
  defp get_connection_status(_), do: "offline"
end
