defmodule NervesHubWeb.Live.Devices.Index do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Firmwares
  alias NervesHub.Products.Product
  alias NervesHub.Tracker

  alias Phoenix.Socket.Broadcast

  alias NervesHubWeb.Components.Pagination

  # FIX
  import NervesHubWeb.DeviceView
  alias NervesHubWeb.LayoutView.DateTimeFormat

  @default_filters %{
    "connection" => "",
    "connection_types" => "",
    "firmware_version" => "",
    "platform" => "",
    "healthy" => "",
    "id" => "",
    "tag" => ""
  }

  @default_page 1
  @default_page_size 25

  def mount(_params, _session, socket) do
    product = socket.assigns.product

    if connected?(socket) do
      socket.endpoint.subscribe("product:#{product.id}:devices")
    end

    socket =
      socket
      |> assign(:current_sort, "identifier")
      |> assign(:sort_direction, :asc)
      |> assign(:page_number, @default_page)
      |> assign(:page_size, @default_page_size)
      |> assign(:page_sizes, [25, 50, 75])
      |> assign(:total_pages, 1)
      |> assign(:firmware_versions, firmware_versions(product.id))
      |> assign(:platforms, Devices.platforms(product.id))
      |> assign(:show_filters, false)
      |> assign(:current_filters, @default_filters)
      |> assign(:currently_filtering, false)
      |> assign(:selected_devices, [])
      |> assign(:target_product, nil)
      |> assign(:valid_tags, true)
      |> assign(:device_tags, "")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign_sort_column(params)
      |> assign_sort_direction(params)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def assign_sort_column(socket, params) do
    if value = params["sort"] do
      assign(socket, :current_sort, value)
    else
      socket
    end
  end

  def assign_sort_direction(socket, params) do
    if value = params["sort_direction"] do
      assign(socket, :sort_direction, value)
    else
      socket
    end
  end

  def assign_paginate_opts(socket, params) do
    if page = params["page"] do
      page_num = String.to_integer(page)

      assign(socket, :page_number, page_num)
    else
      socket
    end
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    page_size = String.to_integer(page_size)

    socket =
      socket
      |> assign(:page_size, page_size)
      |> assign(:page_number, 1)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("update-filters", params, socket) do
    socket =
      socket
      |> assign(:page_number, @default_page)
      |> assign(:current_filters, params)
      |> assign(:currently_filtering, params != @default_filters)
      |> assign(:selected_devices, [])
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("select", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected_devices = socket.assigns.selected_devices

    selected_devices =
      if id in selected_devices do
        selected_devices -- [id]
      else
        [id | selected_devices]
      end

    {:noreply, assign(socket, :selected_devices, selected_devices)}
  end

  def handle_event("deselect-all", _, socket) do
    {:noreply, assign(socket, selected_devices: [])}
  end

  def handle_event("validate-tags", %{"tags" => tags}, socket) do
    if String.contains?(tags, " ") do
      {:noreply, assign(socket, valid_tags: false, device_tags: tags)}
    else
      {:noreply, assign(socket, valid_tags: true, device_tags: tags)}
    end
  end

  def handle_event("tag-devices", %{"tags" => tags}, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.tag_devices(socket.assigns.user, tags)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("target-product", %{"product" => attrs}, socket) do
    target =
      case String.split(attrs, ":") do
        [org_id_str, pid_str, name] ->
          %Product{
            id: String.to_integer(pid_str),
            org_id: String.to_integer(org_id_str),
            name: name
          }

        _ ->
          # ignore attempted move if no product/org selected
          nil
      end

    {:noreply, assign(socket, target_product: target)}
  end

  def handle_event("move-devices", _, socket) do
    %{ok: successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.move_many(socket.assigns.target_product, socket.assigns.user)

    success_ids = Enum.map(successfuls, & &1.id)

    selected_devices = for id <- socket.assigns.selected_devices, id not in success_ids, do: id

    socket =
      assign(socket, selected_devices: selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("disable-updates-for-devices", _, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.disable_updates_for_devices(socket.assigns.user)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("enable-updates-for-devices", _, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.enable_updates_for_devices(socket.assigns.user)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("clear-penalty-box-for-devices", _, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.clear_penalty_box_for_devices(socket.assigns.user)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "connection_change", payload: payload}, socket) do
    # Only sync devices currently on display
    if Map.has_key?(socket.assigns.device_statuses, payload.device_id) do
      device_statuses = Map.put(socket.assigns.device_statuses, payload.device_id, payload.status)
      {:noreply, assign(socket, :device_statuses, device_statuses)}
    else
      {:noreply, socket}
    end
  end

  # Unknown broadcasts get ignored, likely from the device:id:internal channel
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  defp assign_display_devices(
         %{assigns: %{org: org, product: product, page_number: page_number, page_size: page_size}} = socket
       ) do
    opts = %{
      pagination: %{page: page_number, page_size: page_size},
      sort: {socket.assigns.sort_direction, String.to_atom(socket.assigns.current_sort)},
      filters: socket.assigns.current_filters
    }

    page = Devices.get_devices_by_org_id_and_product_id(org.id, product.id, opts)

    statuses =
      Enum.into(page.entries, %{}, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        {device.identifier, Tracker.status(device)}
      end)

    socket
    |> assign(:device_statuses, statuses)
    |> assign_display_devices(page)
  end

  defp assign_display_devices(socket, page) do
    socket
    |> assign(:devices, page.entries)
    |> assign(:page_number, page.page_number)
    |> assign(:page_size, page.page_size)
    |> assign(:total_pages, page.total_pages)
  end

  defp firmware_versions(product_id) do
    Firmwares.get_firmware_versions_by_product(product_id)
  end
end
