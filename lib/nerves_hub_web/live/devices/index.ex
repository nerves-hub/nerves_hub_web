defmodule NervesHubWeb.Live.Devices.Index do
  use NervesHubWeb, :updated_live_view

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products.Product
  alias NervesHub.Tracker

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS
  alias Phoenix.Socket.Broadcast

  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.FilterSidebar
  alias NervesHubWeb.Components.HealthStatus
  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting
  alias NervesHubWeb.LayoutView.DateTimeFormat

  import NervesHubWeb.LayoutView

  @list_refresh_time 10_000

  @default_filters %{
    connection: "",
    connection_type: "",
    firmware_version: "",
    platform: "",
    healthy: "",
    health_status: "",
    identifier: "",
    tags: "",
    updates: "",
    has_no_tags: false,
    alarm_status: "",
    alarm: "",
    metrics_key: "",
    metrics_operator: "gt",
    metrics_value: "",
    deployment_id: "",
    is_pinned: false,
    search: "",
    display_deleted: "exclude",
    only_updating: false
  }

  @filter_types %{
    connection: :string,
    connection_type: :string,
    firmware_version: :string,
    platform: :string,
    healthy: :string,
    health_status: :string,
    identifier: :string,
    tags: :string,
    updates: :string,
    has_no_tags: :boolean,
    alarm_status: :string,
    alarm: :string,
    metrics_key: :string,
    metrics_operator: :string,
    metrics_value: :string,
    deployment_id: :string,
    is_pinned: :boolean,
    search: :string,
    display_deleted: :string,
    only_updating: :boolean
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

  def mount(_params, _session, %{assigns: %{product: product}} = socket) do
    socket
    |> page_title("Devices - #{product.name}")
    |> sidebar_tab(:devices)
    |> assign(:current_sort, "identifier")
    |> assign(:sort_direction, "asc")
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:firmware_versions, firmware_versions(product.id))
    |> assign(:platforms, Devices.platforms(product.id))
    |> assign(:show_filters, false)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> assign(:selected_devices, [])
    |> assign(:target_product, nil)
    |> assign(:progress, %{})
    |> assign(:valid_tags, true)
    |> assign(:device_tags, "")
    |> assign(:total_entries, 0)
    |> assign(:current_alarms, Alarms.get_current_alarm_types(product.id))
    |> assign(:metrics_keys, Metrics.default_metrics())
    |> assign(:deployment_groups, ManagedDeployments.get_deployment_groups_by_product(product))
    |> assign(:available_deployment_groups_for_filtered_platform, [])
    |> assign(:target_deployment_group, nil)
    |> assign(
      :soft_deleted_devices_exist,
      Devices.soft_deleted_devices_exist_for_product?(product.id)
    )
    |> subscribe_and_refresh_device_list_timer()
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
    |> assign(:progress, socket.assigns[:progress] || %{})
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign(:params, unsigned_params)
    |> assign_display_devices()
    |> maybe_assign_available_deployment_groups_for_filtered_platform()
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

    ~p"/org/#{socket.assigns.org.name}/#{socket.assigns.product.name}/devices?#{query}"
  end

  defp subscribe_and_refresh_device_list_timer(socket) do
    if connected?(socket) do
      socket.endpoint.subscribe("product:#{socket.assigns.product.id}:devices")
      Process.send_after(self(), :refresh_device_list, @list_refresh_time)
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

  def handle_event("toggle-filters", %{"toggle" => toggle}, socket) do
    {:noreply, assign(socket, :show_filters, toggle != "true")}
  end

  def handle_event("update-filters", params, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
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

    socket =
      socket
      |> assign(:selected_devices, selected_devices)

    {:noreply, socket}
  end

  def handle_event("select-all", _, socket) do
    selected_devices = socket.assigns.selected_devices

    selected_devices =
      if !socket.assigns.devices.ok? || not Enum.empty?(selected_devices) do
        []
      else
        Enum.map(socket.assigns.devices.result, & &1.id)
      end

    socket
    |> assign(:selected_devices, selected_devices)
    |> noreply()
  end

  def handle_event("deselect-all", _, socket) do
    {:noreply, assign(socket, %{selected_devices: [], available_deployment_groups_for_filtered_platform: []})}
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

    socket
    |> assign(selected_devices: socket.assigns.selected_devices)
    |> put_flash(
      :info,
      "Tagged #{Enum.count(socket.assigns.selected_devices)} selected device(s)."
    )
    |> assign_display_devices()
    |> noreply()
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

  def handle_event("target-deployment-group", %{"deployment_group" => ""}, socket) do
    {:noreply, assign(socket, target_deployment_group: nil)}
  end

  def handle_event("target-deployment-group", %{"deployment_group" => deployment_id}, socket) do
    deployment_group =
      Enum.find(
        socket.assigns.available_deployment_groups_for_filtered_platform,
        &(&1.id == String.to_integer(deployment_id))
      )

    {:noreply, assign(socket, target_deployment_group: deployment_group)}
  end

  def handle_event("move-devices-product", _, socket) do
    %{ok: successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.move_many(socket.assigns.target_product, socket.assigns.user)

    success_ids = Enum.map(successfuls, & &1.id)

    selected_devices = for id <- socket.assigns.selected_devices, id not in success_ids, do: id

    socket
    |> assign(selected_devices: selected_devices)
    |> move_products_toast(successfuls)
    |> assign(:target_product, nil)
    |> assign_display_devices()
    |> noreply()
  end

  def handle_event(
        "move-devices-deployment-group",
        _,
        %{assigns: %{selected_devices: selected_devices, target_deployment_group: target_deployment_group}} = socket
      ) do
    {:ok, %{updated: updated, ignored: ignored}} =
      Devices.move_many_to_deployment_group(selected_devices, target_deployment_group.id)

    socket
    |> assign(:target_deployment_group, nil)
    |> assign_display_devices()
    |> update_flash_for_moving_deployment_group(updated, ignored, target_deployment_group.name)
    |> noreply()
  end

  def handle_event("disable-updates-for-devices", _, socket) do
    %{ok: successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.disable_updates_for_devices(socket.assigns.user)

    socket
    |> assign(selected_devices: socket.assigns.selected_devices)
    |> put_flash(:info, "Disabled updates for #{Enum.count(successfuls)} selected device(s).")
    |> assign_display_devices()
    |> noreply()
  end

  def handle_event("enable-updates-for-devices", _, socket) do
    %{ok: successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.enable_updates_for_devices(socket.assigns.user)

    socket
    |> assign(selected_devices: socket.assigns.selected_devices)
    |> put_flash(:info, "Enabled updates for #{Enum.count(successfuls)} selected device(s).")
    |> assign_display_devices()
    |> noreply()
  end

  def handle_event("clear-penalty-box-for-devices", _, socket) do
    %{ok: successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.clear_penalty_box_for_devices(socket.assigns.user)

    socket
    |> assign(selected_devices: socket.assigns.selected_devices)
    |> put_flash(
      :info,
      "#{Enum.count(successfuls)} selected device(s) cleared from the penalty box."
    )
    |> assign_display_devices()
    |> noreply()
  end

  def handle_event("reboot-device", %{"device_identifier" => device_identifier}, socket) do
    %{org: org, org_user: org_user, user: user} = socket.assigns

    authorized!(:"device:reboot", org_user)

    {:ok, device} = Devices.get_device_by_identifier(org, device_identifier)

    DeviceEvents.reboot(device, user)

    {:noreply, put_flash(socket, :info, "Device Reboot Requested")}
  end

  def handle_event("toggle-device-updates", %{"device_identifier" => device_identifier}, socket) do
    %{org: org, org_user: org_user, user: user} = socket.assigns

    authorized!(:"device:toggle-updates", org_user)

    {:ok, device} = Devices.get_device_by_identifier(org, device_identifier)
    {:ok, device} = Devices.toggle_automatic_updates(device, user)

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

  def handle_info(%Broadcast{event: "fwup_progress", payload: %{device_id: device_id, percent: percent}}, socket)
      when percent > 99 do
    socket
    |> assign(:progress, Map.delete(socket.assigns.progress, device_id))
    |> noreply()
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: %{device_id: device_id, percent: percent}}, socket) do
    socket
    |> assign(:progress, Map.put(socket.assigns.progress, device_id, percent))
    |> noreply()
  end

  # Unknown broadcasts get ignored, likely from the device:id:internal channel
  def handle_info(%Broadcast{}, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh_device_list, socket) do
    Tracer.with_span "NervesHubWeb.Live.Devices.Index.refresh_device_list" do
      Process.send_after(self(), :refresh_device_list, @list_refresh_time)

      if socket.assigns.paginate_opts.total_pages == 1 do
        {:noreply, assign_display_devices(socket)}
      else
        {:noreply, socket}
      end
    end
  end

  defp assign_display_devices(%{assigns: %{product: product, paginate_opts: paginate_opts, user: user}} = socket) do
    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort: {String.to_existing_atom(socket.assigns.sort_direction), String.to_atom(socket.assigns.current_sort)},
      filters: transform_deployment_filter(socket.assigns.current_filters)
    }

    if socket.assigns[:devices] && socket.assigns.devices.ok? do
      socket
    else
      socket
      |> assign(:devices, AsyncResult.loading())
      |> assign(:device_statuses, AsyncResult.loading())
    end
    |> start_async(:update_device_list, fn -> Devices.filter(product, user, opts) end)
  end

  def handle_async(:update_device_list, {:ok, {updated_devices, pager}}, socket) do
    %{devices: old_devices, device_statuses: old_device_statuses, paginate_opts: paginate_opts} =
      socket.assigns

    updated_device_statuses =
      Map.new(updated_devices, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        {device.identifier, Tracker.connection_status(device)}
      end)

    socket
    |> assign(:devices, AsyncResult.ok(old_devices, updated_devices))
    |> assign(:device_statuses, AsyncResult.ok(old_device_statuses, updated_device_statuses))
    |> device_pagination_assigns(paginate_opts, pager)
    |> noreply()
  end

  def handle_async(:update_device_list, {:exit, reason}, socket) do
    %{devices: devices, device_statuses: device_statuses} = socket.assigns

    message =
      "Live.Devices.Index.handle_async:update_device_list failed due to exit: #{inspect(reason)}"

    {:ok, _} = Sentry.capture_message(message, result: :none)

    socket
    |> assign(:devices, AsyncResult.failed(devices, {:exit, reason}))
    |> assign(:device_statuses, AsyncResult.ok(device_statuses, {:exit, reason}))
    |> noreply()
  end

  defp device_pagination_assigns(socket, paginate_opts, pager) do
    paginate_opts =
      paginate_opts
      |> Map.put(:page_number, pager.current_page)
      |> Map.put(:page_size, pager.page_size)
      |> Map.put(:total_pages, pager.total_pages)

    socket
    |> assign(:total_entries, pager.total_count)
    |> assign(:paginate_opts, paginate_opts)
    |> assign(:pager_meta, pager)
  end

  defp transform_deployment_filter(%{deployment_id: ""} = filters), do: Map.delete(filters, :deployment_id)

  defp transform_deployment_filter(%{deployment_id: "-1"} = filters), do: %{filters | deployment_id: nil}

  defp transform_deployment_filter(filters), do: %{filters | deployment_id: String.to_integer(filters.deployment_id)}

  defp update_device_statuses(socket, payload) do
    updated_device_statuses =
      Map.replace(socket.assigns.device_statuses.result, payload.device_id, payload.status)

    {:noreply,
     assign(
       socket,
       :device_statuses,
       AsyncResult.ok(updated_device_statuses)
     )}
  end

  defp move_products_toast(socket, successfuls) do
    %{selected_devices: remaining_selected, target_product: target_product} = socket.assigns

    message =
      [
        "#{Enum.count(successfuls)} device(s) moved to #{target_product.name}.",
        Enum.any?(remaining_selected) &&
          "#{Enum.count(remaining_selected)} devices could not be moved."
      ]
      |> Enum.filter(fn m -> is_binary(m) end)
      |> Enum.join(" ")

    put_flash(socket, :info, message)
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

  defp target_selected?(%{name: name}, value) when name == value, do: [selected: true]
  defp target_selected?(_, _), do: []

  defp devices_table_header(title, value, current_sort, sort_direction) when value == current_sort do
    caret_class = if sort_direction == "asc", do: "up", else: "down"

    assigns = %{value: value, title: title, caret_class: caret_class}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer sort-selected">
      {@title}<i class={"icon-caret icon-caret-#{@caret_class}"} />
    </th>
    """
  end

  defp devices_table_header(title, value, _current_sort, _sort_direction) do
    assigns = %{value: value, title: title}

    ~H"""
    <th phx-click="sort" phx-value-sort={@value} class="pointer">
      {@title}
    </th>
    """
  end

  defp connection_established_at_status(nil), do: "Not seen yet"

  defp connection_established_at_status(latest_connection),
    do: "Last connected at #{connection_established_at_formatted(latest_connection)}"

  defp connection_established_at(nil), do: ""

  defp connection_established_at(latest_connection), do: connection_established_at_formatted(latest_connection)

  defp connection_established_at_formatted(latest_connection) do
    latest_connection
    |> Map.get(:established_at)
    |> DateTimeFormat.from_now()
  end

  defp last_seen_at_status(nil), do: "Not seen yet"

  defp last_seen_at_status(latest_connection), do: "Last seen #{last_seen_formatted(latest_connection)}"

  defp last_seen_at(nil), do: ""
  defp last_seen_at(latest_connection), do: last_seen_formatted(latest_connection)

  defp last_seen_formatted(latest_connection) do
    latest_connection
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

  defp move_alert(nil), do: ""

  defp move_alert(%{name: product_name}) do
    """
    This will move the selected device(s) to the #{product_name} product

    Any existing signing keys the devices may use will attempt to be migrated if they do not exist on the target organization.

    Moving devices may also trigger an update if there are matching deployments on the new product. It is up to the user to ensure any required signing keys are on the device before migrating them to a new product with a new firmware or the device may fail to update.

    Do you wish to continue?
    """
  end

  defp pagination_changes(params) do
    Ecto.Changeset.cast(
      {@default_pagination, @pagination_types},
      params,
      Map.keys(@default_pagination)
    ).changes
  end

  defp filter_changes(params) do
    # when the metrics key is switched from being selected to being an empty value,
    # the metrics value is not cleared, this addresses that.
    params =
      if params["metrics_key"] == "" do
        params
        |> Map.put("metrics_operator", "gt")
        |> Map.put("metrics_value", "")
      else
        params
      end

    Ecto.Changeset.cast({@default_filters, @filter_types}, params, Map.keys(@default_filters), empty_values: []).changes
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

  def show_menu(id, js \\ %JS{}) do
    js
    |> JS.show(transition: "fade-in", to: "##{id}")
  end

  def hide_menu(id, js \\ %JS{}) do
    js
    |> JS.hide(transition: "fade-out", to: "##{id}")
  end

  def fade_in(selector) do
    JS.show(
      to: selector,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end

  defp update_flash_for_moving_deployment_group(socket, updated_count, ignored_count, deployment_group_name) do
    maybe_pluralize =
      &if &1 == 1 do
        &2
      else
        &2 <> "s"
      end

    message =
      case [updated_count, ignored_count] do
        [updated_count, 0] ->
          "#{updated_count} #{maybe_pluralize.(updated_count, "device")} added to deployment #{deployment_group_name}"

        [0, _not_updated_count] ->
          "No devices selected could be added to deployment #{deployment_group_name} because of mismatched firmware"

        [updated_count, not_updated_count] ->
          "#{updated_count} #{maybe_pluralize.(updated_count, "device")} added to deployment #{deployment_group_name}. #{not_updated_count} #{maybe_pluralize.(not_updated_count, "device")} could not be added to deployment because of mismatched firmware"
      end

    put_flash(socket, :info, message)
  end

  defp progress_style(nil) do
    nil
  end

  defp progress_style(progress) do
    """
     background-repeat: no-repeat, no-repeat;
     background-image: linear-gradient(90deg, rgba(16, 185, 129, 1.00) 0%, rgba(16, 185, 129, 1.0) 100%),
                        radial-gradient(circle at 0%, rgba(16, 185, 129, 0.12) 0, rgba(16, 185, 129, 0.12) 60%, rgba(16, 185, 129, 0.0) 100%);
     background-size: #{progress}% 1px, #{progress * 1.1}% 100%;
    """
  end

  defp maybe_assign_available_deployment_groups_for_filtered_platform(
         %{assigns: %{product: product, current_filters: %{platform: platform}}} = socket
       )
       when platform != "" do
    assign(
      socket,
      :available_deployment_groups_for_filtered_platform,
      ManagedDeployments.get_by_product_and_platform(product, platform)
    )
  end

  defp maybe_assign_available_deployment_groups_for_filtered_platform(socket),
    do: assign(socket, :available_deployment_groups_for_filtered_platform, [])

  defp has_results?(%AsyncResult{} = device_async, currently_filtering?) do
    device_async.ok? && (Enum.any?(device_async.result) || currently_filtering?)
  end
end
