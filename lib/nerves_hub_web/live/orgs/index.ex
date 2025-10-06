defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Tracker
  # alias NervesHubWeb.Components.PinnedDevices

  # alias Number.Delimit
  alias Phoenix.Socket.Broadcast

  @pinned_devices_limit 5

  def mount(_params, _session, %{assigns: %{user: user}} = socket) do
    pinned_devices = Devices.get_pinned_devices(user.id)

    statuses =
      Map.new(pinned_devices, fn device ->
        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:page_title, "Organizations")
    |> assign(:show_all_pinned?, false)
    |> assign(:pinned_devices, Devices.get_pinned_devices(user.id))
    |> assign(:device_statuses, statuses)
    |> assign(:device_limit, @pinned_devices_limit)
    |> subscribe()
    |> ok()
  end

  def handle_event("toggle-expand-devices", _, %{assigns: %{show_all_pinned?: show_all?}} = socket) do
    socket
    |> assign(:show_all_pinned?, !show_all?)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:status", payload: payload}, socket) do
    update_device_statuses(socket, payload)
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    update_device_statuses(socket, payload)
  end

  # Ignore unknown broadcasts
  def handle_info(%Broadcast{}, socket), do: {:noreply, socket}

  def subscribe(%{assigns: %{pinned_devices: devices}} = socket) do
    if connected?(socket) do
      Enum.each(devices, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")
      end)
    end

    socket
  end

  defp update_device_statuses(
         %{assigns: %{device_statuses: statuses}} = socket,
         %{device_id: identifier, status: status} = _payload
       ) do
    socket
    |> assign(:device_statuses, Map.put(statuses, identifier, status))
    |> noreply()
  end

  # defp limit_devices(devices) do
  #   {limited_devices, _} = Enum.split(devices, @pinned_devices_limit)

  #   limited_devices
  # end

  # defp format_device_count(nil), do: 0

  # defp format_device_count(count) do
  #   Delimit.number_to_delimited(count, precision: 0)
  # end
end
