defmodule NervesHubWeb.DeviceLive.Index do
  use NervesHubWeb, :live_view

  # For the preloads below
  import Ecto.Query

  require Logger

  alias NervesHub.Accounts
  alias NervesHub.Devices
  alias NervesHub.Firmwares
  alias NervesHub.Products
  alias NervesHub.Products.Product
  alias NervesHub.Tracker
  alias NervesHubWeb.DeviceView

  alias Phoenix.Socket.Broadcast

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

  def render(assigns) do
    DeviceView.render("index.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id
        },
        socket
      ) do
    if connected?(socket) do
      socket.endpoint.subscribe("product:#{product_id}:devices")
    end

    user = Accounts.get_user!(user_id)

    socket =
      socket
      |> assign(:user, user)
      |> assign_new(:orgs, fn ->
        # Taken from the FetchUser plug
        # Duplicated because we can't pass in what the plug already loaded
        org_query = from(o in NervesHub.Accounts.Org, where: is_nil(o.deleted_at))
        product_query = from(p in NervesHub.Products.Product, where: is_nil(p.deleted_at))
        user = Repo.preload(user, orgs: {org_query, products: product_query})
        user.orgs
      end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign(:current_sort, "identifier")
      |> assign(:sort_direction, :asc)
      |> assign(:paginate_opts, %{
        page_number: @default_page,
        page_size: @default_page_size,
        page_sizes: [25, 50, 75],
        total_pages: 0
      })
      |> assign(:firmware_versions, firmware_versions(product_id))
      |> assign(:platforms, Devices.platforms(product_id))
      |> assign(:show_filters, false)
      |> assign(:current_filters, @default_filters)
      |> assign(:currently_filtering, false)
      |> assign(:selected_devices, [])
      |> assign(:target_product, nil)
      |> assign(:valid_tags, true)
      |> assign(:device_tags, "")
      |> assign_display_devices()

    {:ok, socket}
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      socket_error(socket, live_view_error(exception))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_params, _session, socket) do
    socket_error(socket, live_view_error(:update))
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
         %{assigns: %{org: org, product: product, paginate_opts: paginate_opts}} = socket
       ) do
    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort: {socket.assigns.sort_direction, String.to_atom(socket.assigns.current_sort)},
      filters: socket.assigns.current_filters
    }

    page = Devices.get_devices_by_org_id_and_product_id(org.id, product.id, opts)
    health = Devices.get_health_by_org_id_and_product_id(org.id, product.id, opts)

    statuses =
      Enum.into(page.entries, %{}, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        {device.identifier, Tracker.status(device)}
      end)

    socket
    |> assign(:device_statuses, statuses)
    |> assign(:health, health)
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

  defp firmware_versions(product_id) do
    Firmwares.get_firmware_versions_by_product(product_id)
  end
end
