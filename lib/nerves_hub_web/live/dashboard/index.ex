defmodule NervesHubWeb.Live.Dashboard.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    %{product: product} = socket.assigns

    socket
    |> page_title("Dashboard - #{product.name}")
    |> assign_map_devices()
    |> ok()
  end

  defp assign_map_devices(%{assigns: %{org: org, product: product}} = socket) do
    devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)

    map_markers =
      Enum.reduce(devices, [], fn device, acc ->
        generate_map_marker(device, acc)
      end)

    socket
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
  defp get_connection_status(:disconnected), do: "offline"
  defp get_connection_status(:not_seen), do: "offline"
end
