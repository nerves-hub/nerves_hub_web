defmodule NervesHubWeb.Live.Dashboard.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Device

  alias Phoenix.Socket.Broadcast

  @default_refresh 53_000
  @delay 500

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    %{product: product} = socket.assigns

    socket
    |> page_title("Dashboard - #{product.name}")
    |> assign(:time, time())
    |> assign(:next_timer, nil)
    |> assign(:loading?, true)
    |> assign(:mode, "connected")
    |> assign(:device_count, 0)
    |> assign(:marker_count, 0)
    |> refresh_after(1)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_info(%Broadcast{event: "location:updated"}, socket) do
    socket
    |> update_devices_and_markers()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:status"}, socket) do
    socket
    |> update_devices_and_markers()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:change"}, socket) do
    socket
    |> update_devices_and_markers()
    |> noreply()
  end

  def handle_info(:refresh_device_list, socket) do
    socket
    |> update_devices_and_markers()
    |> noreply()
  end

  # Ignore unused messages from the subscription
  def handle_info(_unknown, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def handle_event("map_ready", _params, socket) do
    socket = update_devices_and_markers(socket)
    {:noreply, socket}
  end

  def handle_event("filter-change", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  defp subscribe_to_devices(socket, devices) do
    if connected?(socket) do
      Enum.each(devices, fn device ->
        maybe_subscribe(socket, device)
      end)
    end
  end

  defp subscribed?(device) do
    Registry.count_select(NervesHub.PubSub, [
      {{"device:#{device.identifier}:internal", self(), :_}, [], [true]}
    ]) > 0
  end

  defp maybe_subscribe(socket, device) do
    if not subscribed?(device) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
    end
  end

  defp update_devices_and_markers(%{assigns: %{org: org, product: product}} = socket) do
    t = time()
    duration = t - socket.assigns.time

    if duration >= @delay do
      devices =
        Devices.get_minimal_device_location_by_org_id_and_product_id(org.id, product.id)

      latest_firmwares =
        Deployments.get_deployments_by_product(product)
        |> Enum.reduce(%{}, fn deployment, acc ->
          Map.put(acc, deployment.firmware.uuid, deployment.firmware.platform)
        end)

      map_markers =
        Enum.reduce(devices, [], fn device, acc ->
          generate_map_marker(device, acc, latest_firmwares)
        end)

      subscribe_to_devices(socket, devices)

      socket
      |> assign(:time, t)
      |> assign(:loading?, false)
      |> assign(:device_count, Enum.count(devices))
      |> assign(:marker_count, Enum.count(map_markers))
      |> push_event("markers", %{markers: map_markers})
      # send a refresh on the normal interval after an update
      |> refresh_after(@default_refresh)
    else
      socket
      # send a refresh after the delay, meaning as soon as possible after
      |> refresh_after(@delay - duration)
    end
  end

  defp generate_map_marker(
         %{
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
        s: get_connection_status(connection_status),
        lf: Map.has_key?(latest_firmwares, firmware_uuid),
        l: %{"ng" => longitude, "at" => latitude}
      }

    [new_marker | markers]
  end

  defp generate_map_marker(%Device{} = _device, markers, _) do
    markers
  end

  defp get_connection_status(:connected), do: "connected"
  defp get_connection_status(_), do: "offline"

  defp refresh_after(socket, delay) do
    maybe_cancel_timer(socket.assigns.next_timer)
    timer = Process.send_after(self(), :refresh_device_list, delay)
    assign(socket, :next_timer, timer)
  end

  def maybe_cancel_timer(timer) do
    _ = if timer, do: Process.cancel_timer(timer)
    :ok
  end

  defp time() do
    System.monotonic_time(:millisecond)
  end
end
