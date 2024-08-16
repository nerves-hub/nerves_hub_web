defmodule NervesHubWeb.Live.Devices.Index do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Firmwares
  alias NervesHub.Products.Product
  alias NervesHub.Tracker

  alias Phoenix.Socket.Broadcast

  alias NervesHubWeb.LayoutView.DateTimeFormat

  import NervesHubWeb.LayoutView,
    only: [pagination_links: 1]

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
    %{product: product} = socket.assigns

    socket
    |> page_title("Devices - #{product.name}")
    |> assign(:current_sort, "identifier")
    |> assign(:sort_direction, :asc)
    |> assign(:paginate_opts, %{
      page_number: @default_page,
      page_size: @default_page_size,
      page_sizes: [25, 50, 75],
      total_pages: 0
    })
    |> assign(:firmware_versions, firmware_versions(product.id))
    |> assign(:platforms, Devices.platforms(product.id))
    |> assign(:show_filters, false)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> assign(:selected_devices, [])
    |> assign(:target_product, nil)
    |> assign(:valid_tags, true)
    |> assign(:device_tags, "")
    |> assign_display_devices()
    |> subscribe_and_refresh_device_list()
    |> ok()
  end

  defp subscribe_and_refresh_device_list(socket) do
    if connected?(socket) do
      socket.endpoint.subscribe("product:#{socket.assigns.product.id}:devices")
      Process.send_after(self(), :refresh_device_list, 5000)
      socket
    else
      socket
    end
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  def handle_event("sort", %{"sort" => value}, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{sort_direction: sort_direction} = socket.assigns

    # switch sort direction for column because
    sort_direction = if sort_direction == :desc, do: :asc, else: :desc

    socket =
      socket
      |> assign(sort_direction: sort_direction)
      |> assign_display_devices()

    {:noreply, socket}
  end

  # User has clicked a new column to sort
  def handle_event("sort", %{"sort" => value}, socket) do
    socket =
      socket
      |> assign(:current_sort, value)
      |> assign(:sort_direction, :asc)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event(
        "paginate",
        %{"page" => page_num},
        %{assigns: %{paginate_opts: paginate_opts}} = socket
      ) do
    page_num = String.to_integer(page_num)

    socket =
      socket
      |> assign(:paginate_opts, %{paginate_opts | page_number: page_num})
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    page_size = String.to_integer(page_size)

    paginate_opts =
      socket.assigns.paginate_opts
      |> Map.put(:page_size, page_size)
      |> Map.put(:page_number, 1)

    socket =
      socket
      |> assign(:paginate_opts, paginate_opts)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("toggle-filters", %{"toggle" => toggle}, socket) do
    {:noreply, assign(socket, :show_filters, toggle != "true")}
  end

  def handle_event("update-filters", params, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    socket =
      socket
      |> assign(:paginate_opts, %{paginate_opts | page_number: @default_page})
      |> assign(:current_filters, params)
      |> assign(:currently_filtering, params != @default_filters)
      |> assign(:selected_devices, [])
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("reset-filters", _, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    socket =
      socket
      |> assign(:paginate_opts, %{paginate_opts | page_number: @default_page})
      |> assign(:current_filters, @default_filters)
      |> assign(:currently_filtering, false)
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

  def handle_event("reboot-device", %{"device_identifier" => device_identifier}, socket) do
    %{org: org, org_user: org_user, user: user} = socket.assigns

    authorized!(:"device:reboot", org_user)

    {:ok, device} = Devices.get_device_by_identifier(org, device_identifier)

    AuditLogs.audit!(user, device, "#{user.name} rebooted device #{device.identifier}")

    socket.endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

    {:noreply, put_flash(socket, :info, "Device Reboot Requested")}
  end

  def handle_event("toggle-device-updates", %{"device_identifier" => device_identifier}, socket) do
    %{org: org, org_user: org_user, user: user} = socket.assigns

    authorized!(:"device:toggle-updates", org_user)

    {:ok, device} = Devices.get_device_by_identifier(org, device_identifier)
    {:ok, device} = Devices.toggle_health(device, user)

    socket
    |> put_flash(:info, "Toggled device firmware updates")
    |> assign(:device, device)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:status", payload: payload}, socket) do
    update_device_statuses(socket, payload)
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    update_device_statuses(socket, payload)
  end

  # Unknown broadcasts get ignored, likely from the device:id:internal channel
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh_device_list, socket) do
    Process.send_after(self(), :refresh_device_list, 5000)

    if socket.assigns.paginate_opts.total_pages == 1 do
      {:noreply, assign_display_devices(socket)}
    else
      {:noreply, socket}
    end
  end

  defp assign_display_devices(
         %{assigns: %{org: org, product: product, paginate_opts: paginate_opts}} = socket
       ) do
    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
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

  defp assign_display_devices(%{assigns: %{paginate_opts: paginate_opts}} = socket, page) do
    paginate_opts =
      paginate_opts
      |> Map.put(:page_number, page.page_number)
      |> Map.put(:page_size, page.page_size)
      |> Map.put(:total_pages, page.total_pages)

    socket
    |> assign(:devices, page.entries)
    |> assign(:paginate_opts, paginate_opts)
  end

  defp update_device_statuses(socket, payload) do
    # Only sync devices currently on display
    if Map.has_key?(socket.assigns.device_statuses, payload.device_id) do
      device_statuses = Map.put(socket.assigns.device_statuses, payload.device_id, payload.status)
      {:noreply, assign(socket, :device_statuses, device_statuses)}
    else
      {:noreply, socket}
    end
  end

  defp firmware_versions(product_id) do
    Firmwares.get_firmware_versions_by_product(product_id)
  end

  #
  # MOVE TO COMPONENTS
  #
  defp selected?(filters, field, value) do
    if filters[field] == value do
      [selected: true]
    else
      []
    end
  end

  defp devices_table_header(title, value, current_sort, sort_direction)
       when value == current_sort do
    caret_class = if sort_direction == :asc, do: "up", else: "down"

    assigns = %{value: value, title: title, caret_class: caret_class}

    ~H"""
    <th phx-click="sort" phx-value_sort={@value} class="pointer sort-selected">
      <%= @title %><i class="icon-caret icon-caret-#{@caret_class}" />
    </th>
    """
  end

  defp devices_table_header(title, value, _current_sort, _sort_direction) do
    assigns = %{value: value, title: title}

    ~H"""
    <th phx-click="sort" phx-value_sort={@value} class="pointer">
      <%= @title %>
    </th>
    """
  end

  defp firmware_update_status(device) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        "firmware-penalty-box"

      device.updates_enabled == false ->
        "firmware-disabled"

      true ->
        "firmware-enabled"
    end
  end

  defp firmware_update_title(device) do
    cond do
      Devices.device_in_penalty_box?(device) ->
        "Automatic Penalty Box"

      device.updates_enabled == false ->
        "Firmware Disabled"

      true ->
        "Firmware Enabled"
    end
  end

  defp move_alert(nil), do: ""

  defp move_alert(%{name: product_name}) do
    """
    This will move the selected device(s) to the #{product_name} product

    Any existing signing keys the devices may use will attempt to be migrated if they do not exist on the target organization.

    Moving devices may also trigger an update if there are matching deployments on the new product. It is up to the user to ensure any required signing keys are on the device before migrating them to a new product with a new firmware or the device may fail to update.

    Do you wish to continue?
    """
  end
end
