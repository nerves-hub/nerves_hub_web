defmodule NervesHubWeb.Live.DeploymentGroups.AddDevices do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.Tracker

  alias Phoenix.Socket.Broadcast

  alias NervesHubWeb.LayoutView.DateTimeFormat

  import NervesHubWeb.LayoutView

  @default_filters %{
    connection: "",
    connection_type: "",
    firmware_version: "",
    platform: "",
    healthy: "",
    device_id: "",
    tag: "",
    updates: "",
    has_no_tags: false,
    alarm_status: "",
    alarm: "",
    metrics_key: "",
    metrics_operator: "gt",
    metrics_value: ""
  }

  @filter_types %{
    connection: :string,
    connection_type: :string,
    firmware_version: :string,
    platform: :string,
    healthy: :string,
    device_id: :string,
    tag: :string,
    updates: :string,
    has_no_tags: :boolean,
    alarm_status: :string,
    alarm: :string,
    metrics_key: :string,
    metrics_operator: :string,
    metrics_value: :string,
    deployment_id: :integer
  }

  @default_page 1
  @default_page_size 25

  @default_pagination %{
    page_number: @default_page,
    page_size: @default_page_size,
    page_sizes: [25, 50, 100],
    total_pages: 0
  }

  @pagination_types %{
    page_number: :integer,
    page_size: :integer,
    page_sizes: {:array, :integer},
    total_pages: :integer
  }

  def mount(%{"name" => name}, _session, %{assigns: %{product: product}} = socket) do
    deployment = ManagedDeployments.get_by_product_and_name!(product, name)

    socket
    |> page_title("Devices - #{product.name}")
    |> sidebar_tab(:deployments)
    |> assign(:deployment, deployment)
    |> assign(:current_sort, "identifier")
    |> assign(:sort_direction, "asc")
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:firmware_versions, firmware_versions(product.id))
    |> assign(:platforms, Devices.platforms(product.id))
    |> assign(:current_filters, @default_filters)
    |> assign(:selected_devices, [])
    |> assign(:current_alarms, Alarms.get_current_alarm_types(product.id))
    |> assign(:metrics_keys, Metrics.default_metrics())
    |> ok()
  end

  def handle_params(unsigned_params, _uri, socket) do
    filters = Map.merge(@default_filters, filter_changes(unsigned_params))
    changes = pagination_changes(unsigned_params)
    pagination_opts = Map.merge(@default_pagination, changes)

    socket
    |> assign(:current_sort, Map.get(unsigned_params, "sort", "identifier"))
    |> assign(:sort_direction, Map.get(unsigned_params, "sort_direction", "asc"))
    |> assign(:current_filters, filters)
    |> assign(:paginate_opts, pagination_opts)
    |> assign(:params, unsigned_params)
    |> assign_display_devices()
    |> noreply()
  end

  defp self_path(socket, extra) do
    params = Enum.into(stringify_keys(extra), socket.assigns.params)
    pagination = pagination_changes(params)
    filter = filter_changes(params)
    sort = sort_changes(params)

    query =
      filter
      |> Map.merge(pagination)
      |> Map.merge(sort)

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/deployment_groups/#{socket.assigns.deployment.name}/add_devices?#{query}"
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  def handle_event("sort", %{"sort" => value}, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{sort_direction: sort_direction} = socket.assigns

    # switch sort direction for column because
    sort_direction = if sort_direction == "desc", do: "asc", else: "desc"
    params = %{sort_direction: sort_direction, sort: value}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # User has clicked a new column to sort
  def handle_event("sort", %{"sort" => value}, socket) do
    params = %{sort_direction: "asc", sort: value}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_number" => page_num}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => 1}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  def handle_event(
        "update-filters",
        params,
        %{assigns: %{paginate_opts: paginate_opts}} = socket
      ) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> assign(:selected_devices, [])
    |> push_patch(to: self_path(socket, Map.merge(params, page_params)))
    |> noreply()
  end

  def handle_event("reset-filters", _, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> assign(:selected_devices, [])
    |> push_patch(to: self_path(socket, Map.merge(@default_filters, page_params)))
    |> noreply()
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

  def handle_event("select-all", _, socket) do
    selected_devices = socket.assigns.selected_devices

    selected_devices =
      if Enum.count(selected_devices) > 0 do
        []
      else
        Enum.map(socket.assigns.devices, & &1.id)
      end

    {:noreply, assign(socket, :selected_devices, selected_devices)}
  end

  def handle_event("deselect-all", _, socket) do
    {:noreply, assign(socket, selected_devices: [])}
  end

  def handle_event("add-devices", _, socket) do
    _ =
      Devices.update_many_deployments(socket.assigns.selected_devices, socket.assigns.deployment)

    path =
      ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/deployment_groups/#{socket.assigns.deployment.name}"

    socket
    |> redirect(to: path)
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

  defp assign_display_devices(
         %{assigns: %{product: product, paginate_opts: paginate_opts}} = socket
       ) do
    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort:
        {String.to_existing_atom(socket.assigns.sort_direction),
         String.to_atom(socket.assigns.current_sort)},
      filters: Map.put(socket.assigns.current_filters, :deployment_id, nil)
    }

    page = Devices.filter(product.id, opts)

    statuses =
      Enum.into(page.entries, %{}, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:device_statuses, statuses)
    |> assign_display_devices(page)
  end

  defp assign_display_devices(%{assigns: %{paginate_opts: paginate_opts}} = socket, page) do
    paginate_opts =
      paginate_opts
      |> Map.put(:page_number, page.current_page)
      |> Map.put(:page_size, page.page_size)
      |> Map.put(:total_pages, page.total_pages)

    socket
    |> assign(:devices, page.entries)
    # |> assign(:total_entries, page.total_count)
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
    caret_class = if sort_direction == "asc", do: "up", else: "down"

    assigns = %{value: value, title: title, caret_class: caret_class}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer sort-selected">
      <%= @title %><i class={"icon-caret icon-caret-#{@caret_class}"} />
    </th>
    """
  end

  defp devices_table_header(title, value, _current_sort, _sort_direction) do
    assigns = %{value: value, title: title}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer">
      <%= @title %>
    </th>
    """
  end

  defp last_seen_at_status(connections) do
    case connections do
      [] ->
        "Not seen yet"

      [latest_connection | _] ->
        "Last seen #{last_seen_formatted(latest_connection)}"
    end
  end

  defp last_seen_at(connections) do
    case connections do
      [latest_connection | _] ->
        last_seen_formatted(latest_connection)

      _ ->
        ""
    end
  end

  defp last_seen_formatted(connection) do
    connection
    |> Map.get(:last_seen_at)
    |> DateTimeFormat.from_now()
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

  defp pagination_changes(params) do
    Ecto.Changeset.cast(
      {@default_pagination, @pagination_types},
      params,
      Map.keys(@default_pagination)
    ).changes
  end

  defp filter_changes(params) do
    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters),
      empty_values: []
    ).changes
  end

  @sort_default %{sort_direction: "asc", sort: "identifier"}
  @sort_types %{sort_direction: :string, sort: :string}
  defp sort_changes(params) do
    Ecto.Changeset.cast({@sort_default, @sort_types}, params, Map.keys(@sort_default)).changes
  end

  defp stringify_keys(params) do
    for {key, value} <- params, into: %{} do
      if is_atom(key) do
        {to_string(key), value}
      else
        {key, value}
      end
    end
  end
end
