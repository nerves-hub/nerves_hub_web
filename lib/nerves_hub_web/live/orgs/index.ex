defmodule NervesHubWeb.Live.Orgs.Index do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.PinnedDevices
  alias Phoenix.Socket.Broadcast

  @pinned_devices_limit 5

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{user: user}} = socket) do
    pinned_devices = Devices.get_pinned_devices(user.id)

    statuses =
      Map.new(pinned_devices, fn device ->
        {device.identifier, Tracker.connection_status(device)}
      end)

    socket =
      socket
      |> assign(:page_title, "Organizations")
      |> assign(:show_all_pinned?, false)
      |> assign(:device_info, %{})
      |> assign(:product_device_info, %{})
      |> assign(:pinned_devices, Devices.get_pinned_devices(user.id))
      |> assign(:device_statuses, statuses)
      |> assign(:device_limit, @pinned_devices_limit)
      |> subscribe()

    if connected?(socket), do: send(self(), :load_extras)
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-expand-devices", _, %{assigns: %{show_all_pinned?: show_all?}} = socket) do
    socket
    |> assign(:show_all_pinned?, !show_all?)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:load_extras, socket) do
    org_statuses =
      Connections.get_connection_status_by_orgs(Enum.map(socket.assigns.user.orgs, & &1.id))

    product_ids =
      socket.assigns.user.orgs
      |> Enum.flat_map(& &1.products)
      |> Enum.map(& &1.id)

    product_statuses = Connections.get_connection_status_by_products(product_ids)

    {:noreply,
     socket
     |> assign(:device_info, org_statuses)
     |> assign(:product_device_info, product_statuses)}
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

  defp limit_devices(devices) do
    {limited_devices, _} = Enum.split(devices, @pinned_devices_limit)

    limited_devices
  end
end
