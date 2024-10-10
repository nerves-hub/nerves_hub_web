defmodule NervesHubWeb.Live.Dashboard.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device
  alias NervesHub.Deployments

  alias Phoenix.Socket.Broadcast

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    %{product: product} = socket.assigns

    socket
    |> page_title("Dashboard - #{product.name}")
    |> assign_blank_devices_and_markers()
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
    |> noreply()
  end

  # Ignore unused messages from the subscription
  def handle_info(_unknown, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("map_ready", _params, socket) do
    {:noreply, push_event(socket, "markers", %{markers: socket.assigns.map_markers})}
  end

  def handle_event("filter-change", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  defp start_refresh_cycle(socket) do
    send(self(), :refresh_device_list)
    socket
  end

  defp subscribe_to_devices(socket) do
    if connected?(socket) do
      Enum.each(socket.assigns.devices, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")
      end)

      socket
    else
      socket
    end
  end

  defp assign_blank_devices_and_markers(socket) do
    socket
    |> assign(:devices, [])
    |> assign(:map_markers, [])
    |> assign(:loading?, true)
    |> assign(:mode, "updated")
  end

  defp assign_devices_and_markers(%{assigns: %{org: org, product: product}} = socket) do
    devices = Devices.get_minimal_device_location_by_org_id_and_product_id(org.id, product.id)

    latest_firmwares =
      Deployments.get_deployments_by_product(product.id)
      |> Enum.reduce(%{}, fn deployment, acc ->
        Map.put(acc, deployment.firmware.uuid, deployment.firmware.platform)
      end)

    map_markers =
      Enum.reduce(devices, [], fn device, acc ->
        generate_map_marker(device, acc, latest_firmwares)
      end)

    socket
    |> assign(:devices, devices)
    |> assign(:map_markers, map_markers)
    |> assign(:loading?, false)
    |> push_event("markers", %{markers: map_markers})
  end

  defp generate_map_marker(
         %{
           id: id,
           identifier: identifier,
           connection_status: connection_status,
           longitude: longitude,
           latitude: latitude,
           firmware_uuid: firmware_uuid
         },
         markers,
         latest_firmwares
       )
       when is_number(longitude) and is_number(latitude) do
    new_marker =
      %{
        id: id,
        identifier: identifier,
        status: get_connection_status(connection_status),
        latest_firmware: Map.has_key?(latest_firmwares, firmware_uuid),
        location: %{"longitude" => longitude, "latitude" => latitude}
      }

    [new_marker | markers]
  end

  defp generate_map_marker(%Device{} = _device, markers, _) do
    markers
  end

  defp get_connection_status(:connected), do: "connected"
  defp get_connection_status(_), do: "offline"
end
