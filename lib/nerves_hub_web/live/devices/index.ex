defmodule NervesHubWeb.Live.Devices.Index do
  use NervesHubWeb, :live_view

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Accounts
  alias NervesHub.AuditLogs
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.AdvancedQuery
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.BulkActions
  alias NervesHub.Devices.CACertificates
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.UpdateHistory
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.AddDevice
  alias NervesHubWeb.Components.AdvancedSearch
  alias NervesHubWeb.Components.BulkBar
  alias NervesHubWeb.Components.CAHelpers
  alias NervesHubWeb.Components.DeviceColumns
  alias NervesHubWeb.Components.DeviceFilters
  alias NervesHubWeb.Components.DeviceList
  alias NervesHubWeb.Components.DeviceOnboarding
  alias NervesHubWeb.Components.DevicePeek
  alias NervesHubWeb.Components.DeviceSleep
  alias NervesHubWeb.Components.ListSettingsSidebar
  alias NervesHubWeb.Components.Sorting
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS
  alias Phoenix.Socket.Broadcast

  require OpenTelemetry.Tracer, as: Tracer

  @list_refresh_time 60_000
  # While a product has no devices, how often to look for its first one
  @first_device_check_time 5_000

  # What the phone's sort menu offers: the fields the table's headers sort by.
  @phone_sorts ~w(identifier connection_established_at tags)
  # Delay frequent refresh triggers to this interval
  @refresh_delay 1000

  # Selecting devices only matters for a bulk action, so a role may select
  # them if it may take any of these.
  @bulk_action_permissions [
    :"device:update",
    :"device:tags",
    :"device:push-update",
    :"device:set-deployment-group",
    :"device:toggle-updates",
    :"device:clear-penalty-box"
  ]

  @default_filters DeviceFiltering.default_filters()
  @bulk_menus BulkBar.menus()

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

  @tag_bulk_actions [:tag_devices, :add_tags_to_devices, :remove_tags_from_devices]

  @decorate requires_membership()
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    product = Products.load_shared_secret_auth(scope.product)

    socket
    |> assign(:org, scope.org)
    |> assign(:product, product)
    |> page_title("Devices - #{product.name}")
    |> sidebar_tab(:devices)
    |> assign(:current_sort, "identifier")
    |> assign(:sort_direction, "asc")
    |> assign(:paginate_opts, @default_pagination)
    |> assign(:firmware_versions, [])
    |> assign(:signer_cas, [])
    |> assign(:platforms, [])
    |> assign(:architectures, [])
    |> assign(:advanced_query_tags, [])
    |> assign(:advanced_query_metric_keys, [])
    |> assign(:advanced_query_firmwares, [])
    |> assign(:advanced_query_schema_json, "{}")
    |> assign(:advanced_query_error, nil)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> assign(:selected_devices, [])
    |> assign(:select_all_matching, false)
    |> assign(:selecting?, false)
    |> assign(:target_product, nil)
    |> assign(:move_target_org_ids, Accounts.org_ids_with_role(scope.user, :manage))
    |> assign(:progress, %{})
    |> assign(:valid_tags, true)
    |> assign(:device_tags, "")
    |> assign(:bulk_tags, [])
    |> assign(:tag_operation, "add")
    |> assign(:available_tags, Devices.distinct_tags_for_product(product, scope.user))
    |> assign(:total_entries, 0)
    |> assign(:state_counts, nil)
    |> assign(:product_device_count, nil)
    |> assign(:state_tabs, [])
    |> assign(:reason_tabs, [])
    |> assign(:list_key, nil)
    |> assign(:visible?, true)
    |> assign(:live_refresh_timer, nil)
    |> assign(:live_refresh_pending?, false)
    |> assign(:received_connection_change_identifiers, %{})
    |> assign(:subscribed_device_ids, MapSet.new())
    |> assign(:current_alarms, [])
    |> assign(:metrics_keys, [])
    |> assign(:deployment_groups, [])
    |> assign(:available_deployment_groups_for_filtered_platform, [])
    |> assign(:target_deployment_group, nil)
    |> assign(:available_firmwares_for_filtered_platform, [])
    |> assign(:target_firmware, nil)
    |> assign(:selected_shared_deployment_group, nil)
    |> assign(:selected_have_deployment_groups, false)
    |> assign(:valid_deployment_groups_for_selected, [])
    |> assign(
      :soft_deleted_devices_exist,
      Devices.soft_deleted_devices_exist_for_product?(product.id)
    )
    |> assign(:filters_ready?, false)
    |> assign(:peek_device_id, nil)
    |> assign(:peek, AsyncResult.loading())
    |> assign(:filters_open?, false)
    |> assign(:columns_open?, false)
    |> assign(:bulk_menu, nil)
    |> assign(:list_loading?, false)
    |> assign(:no_match_suggestions, nil)
    |> assign(:awaiting_first_device?, false)
    |> assign(:filter_find, "")
    |> assign(:facets, %{})
    |> assign(:facets_for, nil)
    |> assign(:added_device_id, nil)
    |> refresh_device_list_timer()
    |> ok()
  end

  @decorate requires_membership()
  def handle_params(unsigned_params, _uri, %{assigns: %{product: product}} = socket) do
    filters = DeviceFiltering.parse_filters(unsigned_params)
    sort = DeviceFiltering.parse_sort(unsigned_params)
    changes = pagination_changes(unsigned_params)
    pagination_opts = Map.merge(@default_pagination, changes)

    socket
    |> maybe_clear_selection(filters.state)
    |> assign(:peek_device_id, nil)
    |> assign(:current_sort, sort.sort)
    |> assign(:sort_direction, sort.sort_direction)
    |> assign(:current_filters, filters)
    |> assign(:advanced_query_error, advanced_query_error(filters.advanced_query, product.id))
    |> assign(:paginate_opts, pagination_opts)
    |> assign(:currently_filtering, filters != @default_filters)
    |> assign(:params, unsigned_params)
    |> assign_add_device()
    |> assign_state_tabs()
    |> assign_display_devices()
    |> maybe_assign_available_deployment_groups_for_filtered_platform()
    |> assign_filter_data()
    |> noreply()
  end

  # Add device is a dialog over the list at `/devices/new`, which keeps the
  # list's query so that closing it patches back to the same list. A device
  # given its own secret there is watched until the dialog closes, to say when
  # it connects.
  defp assign_add_device(%{assigns: %{current_scope: scope}} = socket) do
    query = self_query(socket, %{})

    socket
    |> assign(:list_path, ~p"/org/#{scope.org}/#{scope.product}/devices?#{query}")
    |> assign(:new_device_path, ~p"/org/#{scope.org}/#{scope.product}/devices/new?#{query}")
    |> forget_added_device()
  end

  defp forget_added_device(%{assigns: %{live_action: :new}} = socket), do: socket
  defp forget_added_device(socket), do: assign(socket, :added_device_id, nil)

  # A selection belongs to the tab it was made on. Switching tabs could
  # otherwise leave devices selected that the new tab doesn't show.
  defp maybe_clear_selection(%{assigns: %{current_filters: %{state: state}}} = socket, state), do: socket

  defp maybe_clear_selection(socket, _state) do
    socket
    |> assign(:selected_devices, [])
    |> assign(:select_all_matching, false)
    |> assign(:selecting?, false)
    |> update_selected_device_info()
  end

  # Each tab keeps the query, filters, sort and page size, and starts again
  # at the first page. A reason belongs to the Needs attention tab, so the
  # tabs leave it behind.
  defp assign_state_tabs(socket) do
    tabs =
      Enum.map(DeviceList.tabs(), fn tab ->
        params = %{"state" => tab.state, "reason" => "", "page_number" => @default_page}
        Map.put(tab, :path, self_path(socket, params))
      end)

    reason_tabs =
      Enum.map(DeviceList.reason_tabs(), fn tab ->
        Map.put(tab, :path, self_path(socket, %{"reason" => tab.reason, "page_number" => @default_page}))
      end)

    socket
    |> assign(:state_tabs, tabs)
    |> assign(:reason_tabs, reason_tabs)
  end

  defp apply_filters(%{assigns: %{paginate_opts: paginate_opts}} = socket, filters) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> assign(:selected_devices, [])
    |> assign(:select_all_matching, false)
    |> push_patch(to: self_path(socket, Map.merge(filters, page_params)))
    |> noreply()
  end

  defp self_path(%{assigns: %{current_scope: scope}} = socket, extra) do
    ~p"/org/#{scope.org}/#{scope.product}/devices?#{self_query(socket, extra)}"
  end

  # The list's filters, page and sort, with `extra` changed.
  defp self_query(socket, extra) do
    params = Enum.into(stringify_keys(extra), socket.assigns.params)
    pagination = pagination_changes(params)
    filter = DeviceFiltering.filter_changes(params)
    sort = DeviceFiltering.sort_changes(params)

    filter
    |> Map.merge(pagination)
    |> Map.merge(sort)
  end

  defp refresh_device_list_timer(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_device_list, @list_refresh_time)
      socket
    else
      socket
    end
  end

  # On a phone, tapping a card while choosing devices (`selecting?`) selects it
  # rather than opening the peek, as there's no room for a checkbox to aim at.
  @decorate requires_no_permission()
  def handle_event("peek", %{"id" => id}, %{assigns: %{selecting?: true}} = socket) do
    handle_event("select", %{"id" => to_string(id)}, socket)
  end

  # The peek opens on a device of the page the list shows, which is already
  # limited to the devices the user may see.
  @decorate requires_membership()
  def handle_event("peek", %{"id" => id}, socket) do
    case find_listed_device(socket, id) do
      nil -> noreply(socket)
      device -> socket |> open_peek(device) |> noreply()
    end
  end

  # The next or previous device on the page, from the arrow keys. The peek
  # stays put at either end of the page.
  @decorate requires_membership()
  def handle_event("peek-move", %{"by" => by}, %{assigns: %{peek_device_id: id, devices: devices}} = socket)
      when by in [-1, 1] and not is_nil(id) do
    listed = if devices.ok?, do: devices.result, else: []

    with index when is_integer(index) <- Enum.find_index(listed, &(&1.id == id)),
         next_index when next_index >= 0 <- index + by,
         %Device{} = device <- Enum.at(listed, next_index) do
      socket |> open_peek(device) |> noreply()
    else
      _ -> noreply(socket)
    end
  end

  @decorate requires_membership()
  def handle_event("peek-move", _params, socket), do: noreply(socket)

  @decorate requires_membership()
  def handle_event("close-peek", _params, socket) do
    socket
    |> assign(:peek_device_id, nil)
    |> noreply()
  end

  @decorate requires_permission(:"device:reboot")
  def handle_event("peek-reboot", _params, socket) do
    %{current_scope: scope, peek_device_id: id} = socket.assigns

    case find_listed_device(socket, id) do
      nil ->
        noreply(socket)

      device ->
        DeviceEvents.reboot(device, scope.user)

        socket
        |> put_flash(:info, "Reboot requested for #{device.identifier}")
        |> noreply()
    end
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  @decorate requires_membership()
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
  @decorate requires_membership()
  def handle_event("sort", %{"sort" => value}, socket) do
    params = %{sort_direction: "asc", sort: value}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # The phone's sort menu, which has no column headers to click: a field and
  # a direction together, as "identifier:asc".
  @decorate requires_membership()
  def handle_event("sort-by", %{"sort" => value}, socket) do
    case String.split(value, ":") do
      [sort, direction] when sort in @phone_sorts and direction in ~w(asc desc) ->
        socket
        |> push_patch(to: self_path(socket, %{sort: sort, sort_direction: direction}))
        |> noreply()

      _ ->
        noreply(socket)
    end
  end

  @decorate requires_membership()
  def handle_event("paginate", %{"page" => page_num}, socket) do
    params = %{"page_number" => page_num}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("set-paginate-opts", %{"page-size" => page_size}, socket) do
    params = %{"page_size" => page_size, "page_number" => 1}

    socket
    |> push_patch(to: self_path(socket, params))
    |> noreply()
  end

  # The Filters panel's form, whose multi-choice filters arrive as lists.
  @decorate requires_membership()
  def handle_event("update-filters", params, socket) do
    apply_filters(socket, DeviceFilters.join_choices(params))
  end

  # Resets what the Filters panel sets, keeping the tab and the query.
  @decorate requires_membership()
  def handle_event("reset-filters", _, socket) do
    apply_filters(socket, Map.drop(@default_filters, [:state, :reason, :advanced_query]))
  end

  # A filter's token, or a Clear link in the Filters panel. Clearing the metric
  # clears its comparison too.
  @decorate requires_membership()
  def handle_event("remove-filter", %{"key" => key}, socket) do
    case Enum.find(DeviceFilters.applied(socket.assigns.current_filters), &(to_string(&1) == key)) do
      nil ->
        noreply(socket)

      key ->
        apply_filters(socket, filter_removal(key))
    end
  end

  # The Filters panel is open while its choices' counts are wanted, and it
  # covers the peek, so opening it closes the peek.
  @decorate requires_membership()
  def handle_event("open-filters", _, socket) do
    socket
    |> assign(:filters_open?, true)
    |> assign(:columns_open?, false)
    |> assign(:bulk_menu, nil)
    |> assign(:filter_find, "")
    |> assign(:peek_device_id, nil)
    |> assign_facets()
    |> noreply()
  end

  # The floating bulk bar opens one popover at a time; asking for the open one
  # again closes it, as does opening it over the Filters or Columns panel.
  @decorate requires_membership()
  def handle_event("bulk-menu", %{"menu" => menu}, socket) when menu in @bulk_menus do
    menu = if socket.assigns.bulk_menu != menu, do: menu

    socket
    |> assign(:bulk_menu, menu)
    |> assign(:filters_open?, false)
    |> assign(:columns_open?, false)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("close-bulk-menu", _, socket) do
    socket
    |> assign(:bulk_menu, nil)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("close-filters", _, socket) do
    socket
    |> assign(:filters_open?, false)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("find-filter", %{"find" => find}, socket) do
    socket
    |> assign(:filter_find, String.slice(find, 0, 100))
    |> noreply()
  end

  # Free-text input is applied as its rewritten `search like "%text%"` form
  # (the canonical query from `AdvancedQuery.interpret/2`), so the search box
  # shows the query language equivalent of what was typed.
  @decorate requires_membership()
  def handle_event("apply-advanced-query", %{"query" => raw_query}, %{assigns: %{current_scope: scope}} = socket) do
    query = String.trim(raw_query)

    case query != "" && AdvancedQuery.interpret(query, scope.product.id) do
      false ->
        apply_advanced_query(socket, query)

      {:ok, canonical_query, _ast} ->
        apply_advanced_query(socket, canonical_query)

      {:error, message, _position} ->
        socket
        |> assign(:advanced_query_error, message)
        |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("clear-advanced-query", _, socket) do
    apply_advanced_query(socket, "")
  end

  # The Columns panel sits where the Filters panel and the peek do, so it
  # closes them.
  @decorate requires_membership()
  def handle_event("open-columns", _, socket) do
    socket
    |> assign(:columns_open?, true)
    |> assign(:filters_open?, false)
    |> assign(:bulk_menu, nil)
    |> assign(:peek_device_id, nil)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("close-columns", _, socket) do
    socket
    |> assign(:columns_open?, false)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("update-columns", params, socket) do
    chosen = List.wrap(params["columns"])

    socket
    |> save_columns(Enum.filter(DeviceColumns.columns(), &(to_string(&1) in chosen)))
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("show-all-columns", _, socket) do
    socket
    |> save_columns(DeviceColumns.columns())
    |> noreply()
  end

  @decorate authorizes_in_body(:any_bulk_action_permission)
  def handle_event("select", %{"id" => id_str}, socket) do
    may_select_devices!(socket.assigns.current_scope)

    %{selected_devices: selected_devices, devices: devices} = socket.assigns

    with {device_id, ""} <- Integer.parse(id_str),
         device when not is_nil(device) <- Enum.find(devices.result, fn device -> device.id == device_id end) do
      selected_devices =
        if device.id in selected_devices do
          selected_devices -- [device.id]
        else
          [device.id | selected_devices]
        end

      socket
      |> assign(:selected_devices, selected_devices)
      |> assign(:select_all_matching, false)
      |> update_selected_device_info()
      |> noreply()
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid device selection")}
    end
  end

  @decorate authorizes_in_body(:any_bulk_action_permission)
  def handle_event("select-all", _, socket) do
    may_select_devices!(socket.assigns.current_scope)

    %{selected_devices: selected_devices, devices: devices} = socket.assigns

    with {:loaded, true} <- {:loaded, devices.ok?},
         false <- Enum.any?(selected_devices) do
      selected_devices = Enum.map(devices.result, & &1.id)

      socket
      |> assign(:selected_devices, selected_devices)
      |> update_selected_device_info()
      |> noreply()
    else
      {:loaded, false} ->
        {:noreply, put_flash(socket, :error, "Device list hasn't loaded yet")}

      _ ->
        socket
        |> assign(:selected_devices, [])
        |> update_selected_device_info()
        |> noreply()
    end
  end

  # The phone's Select button: the cards show checkboxes, and tapping one
  # selects it, until Done ("deselect-all").
  @decorate authorizes_in_body(:any_bulk_action_permission)
  def handle_event("start-selecting", _, socket) do
    may_select_devices!(socket.assigns.current_scope)

    socket
    |> assign(:selecting?, true)
    |> assign(:peek_device_id, nil)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("deselect-all", _, socket) do
    socket
    |> assign(%{
      selected_devices: [],
      select_all_matching: false,
      selecting?: false,
      available_deployment_groups_for_filtered_platform: []
    })
    |> update_selected_device_info()
    |> noreply()
  end

  @decorate authorizes_in_body(:any_bulk_action_permission)
  def handle_event("select-all-matching", _, socket) do
    may_select_devices!(socket.assigns.current_scope)

    %{devices: devices} = socket.assigns

    selected_devices = Enum.map(devices.result, & &1.id)

    socket
    |> assign(:selected_devices, selected_devices)
    |> assign(:select_all_matching, true)
    |> update_selected_device_info()
    |> noreply()
  end

  # `new_tag` is the tag being typed into the Tags popover, before it becomes a
  # chip; `tags` holds the chips already added.
  @decorate requires_membership()
  def handle_event("validate-tags", params, socket) do
    typed = Map.get(params, "new_tag", "")

    socket
    |> assign(:valid_tags, not String.contains?(typed, " "))
    |> assign(:device_tags, typed)
    |> assign(:tag_operation, tag_operation(params))
    |> noreply()
  end

  # Enter, a comma or picking a suggestion in the Tags popover turns what was
  # typed into chips. Spaces separate tags here too, since a tag can't hold one.
  @decorate requires_membership()
  def handle_event("bulk-add-tag", %{"tag" => text}, socket) do
    added = text |> String.split([",", " "], trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    socket
    |> update(:bulk_tags, &Enum.uniq(&1 ++ added))
    |> assign(:device_tags, "")
    |> assign(:valid_tags, true)
    |> noreply()
  end

  @decorate requires_membership()
  def handle_event("bulk-remove-tag", %{"tag" => tag}, socket) do
    socket
    |> update(:bulk_tags, &List.delete(&1, tag))
    |> noreply()
  end

  @decorate requires_permission(:"device:tags")
  def handle_event("tag-devices", params, socket) do
    tags = submitted_tags(params)

    # A phx-submit command only sends its first push, so the handler closes
    # the popover itself (here and in every bulk action below).
    socket = assign(socket, bulk_menu: nil, bulk_tags: [], device_tags: "", valid_tags: true)

    bulk_action = tag_bulk_action(tag_operation(params))

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, bulk_action, [socket.assigns.current_scope.user, tags])
    else
      %{selected_devices: selected_devices, current_scope: scope} = socket.assigns
      {applied, attempted} = tag_action_wording(bulk_action)

      with {:devices, devices} when is_list(devices) and devices != [] <-
             {:devices, Devices.get_devices_by_id(scope, selected_devices)},
           result = bulk_update_tags(bulk_action, devices, scope.user, tags),
           {:successful, true} <- {:successful, Enum.any?(result[:ok])},
           {:has_errors, false, _result} <- {:has_errors, Enum.any?(result[:error]), result} do
        socket
        |> put_flash(:info, "#{applied} all selected device(s).")
        |> assign_display_devices()
        |> noreply()
      else
        {:devices, _} ->
          {:noreply, put_flash(socket, :error, "You haven't selected any devices")}

        {:successful, false} ->
          {:noreply, put_flash(socket, :error, "#{attempted} failed for all selected device(s).")}

        {:has_errors, true, result} ->
          socket
          |> put_flash(
            :info,
            "#{applied} #{Enum.count(result[:ok])} devices, #{Enum.count(result[:error])} devices had errors."
          )
          |> assign(selected_devices: Enum.map(result[:ok], & &1.id))
          |> assign_display_devices()
          |> noreply()
      end
    end
  end

  @decorate requires_membership()
  def handle_event("target-product", %{"product_id" => ""}, socket) do
    {:noreply, assign(socket, target_product: nil)}
  end

  @decorate requires_permission(:"device:update")
  def handle_event("target-product", %{"product_id" => pid_str}, socket) do
    with {product_id, ""} <- Integer.parse(pid_str),
         # Moving hands the devices to the target product's org, so the user
         # must be able to manage devices there too, as the API's move requires.
         {:ok, product} <- Products.get_by_id(socket.assigns.current_scope, product_id, :manage) do
      {:noreply, assign(socket, target_product: product)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid product selection")}
    end
  end

  @decorate requires_membership()
  def handle_event("target-deployment-group", params, socket) when not is_map_key(params, "deployment_group") do
    {:noreply, assign(socket, target_deployment_group: nil)}
  end

  @decorate requires_membership()
  def handle_event("target-deployment-group", %{"deployment_group" => ""}, socket) do
    {:noreply, assign(socket, target_deployment_group: nil)}
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("target-deployment-group", %{"deployment_group" => deployment_id_str}, socket) do
    %{
      available_deployment_groups_for_filtered_platform: available,
      valid_deployment_groups_for_selected: valid
    } = socket.assigns

    with {deployment_id, ""} <- Integer.parse(deployment_id_str),
         deployment_group when not is_nil(deployment_group) <-
           Enum.find(available ++ valid, &(&1.id == deployment_id)) do
      {:noreply, assign(socket, target_deployment_group: deployment_group)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid deployment group selection")}
    end
  end

  @decorate requires_permission(:"device:update")
  def handle_event("move-devices-product", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{
      selected_devices: selected_devices,
      target_product: target_product,
      current_scope: scope
    } = socket.assigns

    if socket.assigns.select_all_matching do
      case still_allowed_target(scope, target_product) do
        {:ok, target_product} -> start_bulk_async(socket, :move_many, [target_product, scope.user])
        :no_product -> {:noreply, put_flash(socket, :error, "You haven't selected a product")}
        :not_allowed -> {:noreply, refuse_target_product(socket)}
      end
    else
      with {:devices_selected, true} <- {:devices_selected, selected_devices != []},
           {:product_selected, true} <- {:product_selected, target_product != nil},
           {:ok, target_product} <- still_allowed_target(scope, target_product),
           devices when is_list(devices) and devices != [] <- Devices.get_devices_by_id(scope, selected_devices),
           result = BulkActions.move_many(devices, target_product, scope.user),
           {:successful, true} <- {:successful, Enum.any?(result[:ok])},
           {:has_errors, false, _result} <- {:has_errors, Enum.any?(result[:error]), result} do
        socket
        |> assign(:target_product, nil)
        |> assign_display_devices()
        |> put_flash(:info, "All selected devices successfully moved to #{target_product.name}")
        |> noreply()
      else
        {:devices_selected, false} ->
          {:noreply, put_flash(socket, :error, "You haven't selected any devices")}

        {:product_selected, false} ->
          {:noreply, put_flash(socket, :error, "You haven't selected a product")}

        :not_allowed ->
          {:noreply, refuse_target_product(socket)}

        {:successful, false} ->
          {:noreply, put_flash(socket, :error, "No devices were successfully moved to #{target_product.name}")}

        {:has_errors, true, result} ->
          socket
          |> put_flash(
            :info,
            "#{Enum.count(result[:ok])} devices were successfully moved to #{target_product.name}, and #{Enum.count(result[:error])} devices had errors and couldn't be moved"
          )
          |> assign(selected_devices: Enum.map(result[:ok], & &1.id))
          |> assign_display_devices()
          |> noreply()
      end
    end
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("move-devices-deployment-group", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{
      assigns: %{
        current_scope: scope,
        selected_devices: selected_devices,
        target_deployment_group: target_deployment_group
      }
    } = socket

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, :move_many_to_deployment_group, [target_deployment_group.id, scope.user])
    else
      with %{updated: updated_count, ignored: ignored_count} = result <-
             BulkActions.move_many_to_deployment_group(selected_devices, target_deployment_group.id, scope.user),
           {:successful, true} <- {:successful, updated_count > 0},
           {:has_ignores, false, _result} <- {:has_ignores, ignored_count > 0, result} do
        socket
        |> assign(:target_deployment_group, nil)
        |> assign_display_devices()
        |> put_flash(:info, "All selected devices were added to deployment #{target_deployment_group.name}")
        |> noreply()
      else
        {:successful, false} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "No devices selected could be added to deployment #{target_deployment_group.name} because of mismatched firmware"
           )}

        {:has_ignores, true, result} ->
          socket
          |> put_flash(
            :info,
            "#{result.updated} #{maybe_pluralize(result.updated, "device")} added to deployment #{target_deployment_group.name}. #{result.ignored} #{maybe_pluralize(result.ignored, "device")} could not be added to deployment because of mismatched firmware"
          )
          |> assign(:target_deployment_group, nil)
          |> assign_display_devices()
          |> noreply()
      end
    end
  end

  @decorate requires_membership()
  def handle_event("target-firmware", %{"firmware" => ""}, socket) do
    {:noreply, assign(socket, target_firmware: nil)}
  end

  @decorate requires_permission(:"device:push-update")
  def handle_event("target-firmware", %{"firmware" => firmware_uuid}, socket) do
    firmware =
      Enum.find(
        socket.assigns.available_firmwares_for_filtered_platform,
        &(&1.uuid == firmware_uuid)
      )

    {:noreply, assign(socket, target_firmware: firmware)}
  end

  @decorate requires_permission(:"device:push-update")
  def handle_event("push-firmware-to-devices", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{assigns: %{current_scope: scope, selected_devices: selected_devices, target_firmware: firmware}} =
      socket

    %{org: org} = scope

    devices = Devices.get_devices_by_id(scope, selected_devices)

    opts =
      if proxy_url = get_in(org.settings.firmware_proxy_url) do
        [firmware_proxy_url: proxy_url]
      else
        []
      end

    sent_count =
      Enum.count(devices, fn device ->
        case DeviceEvents.manual_update(device, firmware, scope.user, opts) do
          {:ok, _} -> true
          _ -> false
        end
      end)

    socket
    |> assign(:target_firmware, nil)
    |> put_flash(:info, "Firmware update sent to #{sent_count} device(s).")
    |> noreply()
  end

  @decorate requires_permission(:"device:set-deployment-group")
  def handle_event("remove-devices-from-deployment-group", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, :remove_many_from_deployment_group, [])
    else
      %{ok: count} = BulkActions.remove_many_from_deployment_group({selected_devices, scope.product})

      socket
      |> assign_display_devices()
      |> put_flash(:info, "#{count} device(s) removed from their deployment group.")
      |> noreply()
    end
  end

  @decorate requires_permission(:"device:toggle-updates")
  def handle_event("disable-updates-for-devices", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, :disable_updates_for_devices, [scope.user])
    else
      %{ok: successfuls} =
        Devices.get_devices_by_id(scope, selected_devices)
        |> BulkActions.disable_updates_for_devices(scope.user)

      socket
      |> assign(selected_devices: selected_devices)
      |> put_flash(:info, "Disabled updates for #{Enum.count(successfuls)} selected device(s).")
      |> assign_display_devices()
      |> noreply()
    end
  end

  @decorate requires_permission(:"device:toggle-updates")
  def handle_event("enable-updates-for-devices", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, :enable_updates_for_devices, [scope.user])
    else
      %{ok: successfuls} =
        Devices.get_devices_by_id(scope, selected_devices)
        |> BulkActions.enable_updates_for_devices(scope.user)

      socket
      |> assign(selected_devices: selected_devices)
      |> put_flash(:info, "Enabled updates for #{Enum.count(successfuls)} selected device(s).")
      |> assign_display_devices()
      |> noreply()
    end
  end

  @decorate requires_permission(:"device:clear-penalty-box")
  def handle_event("clear-penalty-box-for-devices", _, socket) do
    socket = assign(socket, :bulk_menu, nil)

    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    if socket.assigns.select_all_matching do
      start_bulk_async(socket, :clear_penalty_box_for_devices, [scope.user])
    else
      %{ok: successfuls} =
        Devices.get_devices_by_id(scope, selected_devices)
        |> BulkActions.clear_penalty_box_for_devices(scope.user)

      socket
      |> assign(selected_devices: selected_devices)
      |> put_flash(
        :info,
        "#{Enum.count(successfuls)} selected device(s) cleared from the penalty box."
      )
      |> assign_display_devices()
      |> noreply()
    end
  end

  @decorate requires_membership()
  def handle_event("page_visibility_change", %{"visible" => visible?}, socket) do
    socket
    |> then(fn socket ->
      # refresh if switching to visible from non-visible
      if not socket.assigns.visible? and visible? do
        safe_refresh(socket)
      else
        socket
      end
    end)
    |> assign(visible?: visible?)
    |> noreply()
  end

  def handle_info({:async_update_complete, key, message}, socket) do
    socket
    |> put_flash(key, message)
    |> assign_display_devices()
    |> noreply()
  end

  def handle_info(%Broadcast{topic: topic, event: "connection:change", payload: %{status: "online"}}, socket) do
    device_id = parse_device_id(topic)

    if device_id == socket.assigns.added_device_id do
      send_update(AddDevice, id: "add-device", connected: true)
    end

    socket
    |> update(:received_connection_change_identifiers, &Map.put(&1, device_id, "online"))
    |> safe_refresh()
    |> update_device_statuses(device_id, "online")
    |> update_firmware_progress(device_id)
    |> noreply()
  end

  def handle_info(%Broadcast{topic: topic, event: "connection:change", payload: %{status: "offline"} = payload}, socket) do
    device_id = parse_device_id(topic)
    status = offline_status(payload)

    socket
    |> update(:received_connection_change_identifiers, &Map.put(&1, device_id, status))
    |> update_device_statuses(device_id, status)
    |> close_listed_connection(device_id, payload)
    |> noreply()
  end

  def handle_info(%Broadcast{topic: topic, event: "firmware_update_progress", payload: %{"stage" => "expired"}}, socket) do
    device_id = parse_device_id(topic)

    socket
    |> update(:progress, &Map.put(&1, device_id, %{stage: "update aborted", percent: 0}))
    |> noreply()
  end

  def handle_info(
        %Broadcast{topic: topic, event: "firmware_update_progress", payload: %{"stage" => "completed"}},
        socket
      ) do
    device_id = parse_device_id(topic)

    socket
    |> update(:progress, &Map.put(&1, device_id, %{stage: "completed, restarting", percent: 100}))
    |> noreply()
  end

  def handle_info(%Broadcast{topic: topic, event: "firmware_update_progress", payload: payload}, socket) do
    device_id = parse_device_id(topic)

    socket
    |> update(:progress, &Map.put(&1, device_id, %{stage: payload["stage"], percent: payload["progress"] || 0}))
    |> noreply()
  end

  # Unknown broadcasts get ignored, likely from the internal:device:id channel
  def handle_info(%Broadcast{}, socket) do
    socket
    |> safe_refresh()
    |> noreply()
  end

  # The device the Add device dialog just added: list it, and watch it.
  def handle_info({AddDevice, {:added, device}}, socket) do
    socket
    |> assign(:added_device_id, device.id)
    |> assign_display_devices()
    |> noreply()
  end

  def handle_info(:refresh_device_list, %{assigns: %{visible?: true}} = socket) do
    Tracer.with_span "NervesHubWeb.Live.Devices.Index.refresh_device_list" do
      Process.send_after(self(), :refresh_device_list, @list_refresh_time)

      socket
      |> safe_refresh()
      |> noreply()
    end
  end

  def handle_info(:refresh_device_list, socket) do
    noreply(socket)
  end

  def handle_info(:await_first_device, socket) do
    socket = assign(socket, :awaiting_first_device?, false)

    if socket.assigns.product_device_count == 0 and socket.assigns.visible? do
      socket
      |> assign_display_devices()
      |> noreply()
    else
      noreply(socket)
    end
  end

  def handle_info(:live_refresh, socket) do
    if socket.assigns.visible? and socket.assigns.live_refresh_pending? do
      Tracer.with_span "NervesHubWeb.Live.Devices.Index.live_refresh_device_list" do
        assign_display_devices(socket)
      end
    else
      socket
    end
    |> assign(:live_refresh_timer, nil)
    |> assign(:live_refresh_pending?, false)
    |> noreply()
  end

  # Every one of these depends only on the product, so sorting, paging and
  # filtering the list cannot change them - and `handle_params/3` runs on all
  # three. Load them once and leave them; a failed load clears `filters_ready?`
  # and gets retried on the next navigation.
  defp assign_filter_data(%{assigns: %{filters_ready?: true}} = socket), do: socket

  defp assign_filter_data(%{assigns: %{current_scope: %{product: product, user: user}}} = socket) do
    socket
    |> start_async(:update_filter_data, fn ->
      distinct_metric_keys = Metrics.distinct_keys(product.id)

      [
        current_alarms: Alarms.get_current_alarm_types(product.id),
        metrics_keys: Enum.sort(Enum.uniq(Metrics.default_metrics() ++ distinct_metric_keys)),
        deployment_groups: ManagedDeployments.get_deployment_groups_by_product(product),
        firmware_versions: Devices.firmware_versions(product.id),
        signer_cas: CACertificates.signer_cas_for_product(product.id),
        platforms: Devices.platforms(product.id),
        architectures: Devices.architectures(product.id),
        advanced_query_tags: Devices.distinct_tags(product.id, user),
        advanced_query_metric_keys: distinct_metric_keys,
        advanced_query_firmwares: Firmwares.firmware_versions_and_uuids(product.id)
      ]
    end)
  end

  # How many devices each choice in the Filters panel would give, alongside the
  # other filters. Only counted while the panel is open, and the firmware
  # versions and alarms it lists have loaded. A filter change counts them once
  # its list has arrived (`recount_facets/1`), not alongside it: the list is
  # what someone is waiting for, and a list superseded by another change never
  # starts its counts.
  defp assign_facets(%{assigns: %{filters_open?: true, filters_ready?: true, current_scope: scope} = assigns} = socket) do
    key = facets_key(assigns)
    opts = %{filters: DeviceFiltering.transform_deployment_filter(assigns.current_filters)}
    facets = DeviceFilters.facets(assigns.current_filters, assigns.firmware_versions, assigns.current_alarms)

    socket
    |> assign(:facets_for, key)
    |> start_async(:load_facets, fn ->
      {key, Devices.facet_counts(scope.product, scope.user, opts, facets)}
    end)
  end

  defp assign_facets(socket), do: socket

  defp facets_key(assigns), do: :erlang.phash2(assigns.current_filters)

  # Counts the facets for the filters the list now shows, unless they're
  # already counted (or being counted), as they are after a refresh.
  defp recount_facets(%{assigns: assigns} = socket) do
    if assigns.facets_for == facets_key(assigns), do: socket, else: assign_facets(socket)
  end

  defp apply_advanced_query(%{assigns: %{paginate_opts: paginate_opts}} = socket, query) do
    page_params = %{"page_number" => @default_page, "page_size" => paginate_opts.page_size}

    socket
    |> assign(:advanced_query_error, nil)
    |> push_patch(to: self_path(socket, Map.merge(%{"advanced_query" => query}, page_params)))
    |> noreply()
  end

  defp advanced_query_error(query, product_id) do
    case query != "" && AdvancedQuery.interpret(query, product_id) do
      false -> nil
      {:ok, _canonical_query, _ast} -> nil
      {:error, message, _position} -> message
    end
  end

  defp advanced_query_schema_json(assigns) do
    metric_columns =
      Enum.map(assigns.advanced_query_metric_keys, &(AdvancedQuery.Schema.metric_prefix() <> &1))

    columns = AdvancedQuery.Schema.columns() ++ metric_columns

    Jason.encode!(%{
      columns: columns,
      operators: Map.new(columns, &{&1, AdvancedQuery.Schema.operators(&1)}),
      values: %{
        "platform" => Enum.reject(assigns.platforms, &is_nil/1),
        "architecture" => Enum.reject(assigns.architectures, &is_nil/1),
        "connection" => AdvancedQuery.Schema.connection_values(nil),
        "last_seen" => AdvancedQuery.Schema.last_seen_values(nil),
        "tags" => assigns.advanced_query_tags ++ [AdvancedQuery.Schema.not_set_value()],
        "health_status" => AdvancedQuery.Schema.health_status_values(nil),
        "firmware_validation_status" => AdvancedQuery.Schema.firmware_validation_status_values(nil),
        "connection_type" => AdvancedQuery.Schema.connection_type_values(nil),
        "updates" => AdvancedQuery.Schema.updates_values(nil),
        "alarm_status" => AdvancedQuery.Schema.alarm_status_values(nil),
        "alarm" => assigns.current_alarms,
        "deleted" => AdvancedQuery.Schema.boolean_values(nil),
        "update_status" => AdvancedQuery.Schema.update_status_values(nil),
        "firmware" => firmware_suggestion_values(assigns.advanced_query_firmwares),
        "deployment_group" => Enum.map(assigns.deployment_groups, & &1.name) ++ [AdvancedQuery.Schema.not_set_value()],
        "signer_ca" => signer_ca_suggestion_values(assigns.signer_cas)
      }
    })
  end

  # Signer CA autosuggest shows the CA's description (falling back to its
  # formatted serial), but the query value is the serial.
  defp signer_ca_suggestion_values(signer_cas) do
    Enum.map(signer_cas, &%{label: CAHelpers.label(&1), value: &1.serial}) ++
      [AdvancedQuery.Schema.not_set_value()]
  end

  # Firmware autosuggest shows a friendly "<version> - <short uuid>" label, but
  # the query value is the full UUID.
  defp firmware_suggestion_values(firmwares) do
    Enum.map(firmwares, fn %{version: version, uuid: uuid} ->
      %{label: "#{version} - #{String.slice(uuid, 0, 7)}", value: uuid}
    end)
  end

  defp assign_display_devices(%{assigns: %{current_scope: scope, paginate_opts: paginate_opts}} = socket) do
    list_key = list_key(socket.assigns)

    opts = %{
      pagination: %{page: paginate_opts.page_number, page_size: paginate_opts.page_size},
      sort:
        {String.to_existing_atom(socket.assigns.sort_direction), String.to_existing_atom(socket.assigns.current_sort)},
      filters: DeviceFiltering.transform_deployment_filter(socket.assigns.current_filters)
    }

    if socket.assigns[:devices] && socket.assigns.devices.ok? do
      # A different list (filters, tab, page or sort) shows the old one
      # dimmed until it arrives; a refresh of the same list doesn't.
      assign(socket, :list_loading?, list_key != socket.assigns.list_key)
    else
      socket
      |> assign(:devices, AsyncResult.loading())
      |> assign(:device_statuses, AsyncResult.loading())
    end
    |> start_async(:update_device_list, fn ->
      {updated_devices, pager} = Devices.filter(scope.product, scope.user, opts)
      state_counts = Devices.state_counts(scope.product, scope.user, opts)
      product_count = Map.get(Devices.count_by_product([scope.product.id], scope.user), scope.product.id, 0)

      {updated_devices, pager, state_counts, product_count, list_key}
    end)
  end

  def handle_async(:update_device_list, {:ok, {updated_devices, pager, state_counts, product_count, list_key}}, socket) do
    %{devices: old_devices, device_statuses: old_device_statuses, paginate_opts: paginate_opts} =
      socket.assigns

    updated_device_statuses =
      Map.new(updated_devices, fn device ->
        status = socket.assigns.received_connection_change_identifiers[device.id]

        {device.id, status || device_status(device)}
      end)

    socket
    |> sync_device_subscriptions(updated_devices)
    |> assign(:devices, AsyncResult.ok(old_devices, updated_devices))
    |> assign(:device_statuses, AsyncResult.ok(old_device_statuses, updated_device_statuses))
    |> assign(:received_connection_change_identifiers, %{})
    |> assign(:state_counts, state_counts)
    |> assign(:product_device_count, product_count)
    |> assign(:list_key, list_key)
    |> assign(:list_loading?, false)
    |> device_pagination_assigns(paginate_opts, pager)
    |> assign_no_match_suggestions(updated_devices)
    |> recount_facets()
    |> await_first_device(product_count)
    |> then(fn socket ->
      progress =
        Enum.reduce(updated_devices, %{}, fn device, acc ->
          if device.inflight_update do
            Map.put(acc, device.id, %{
              stage: to_string(device.inflight_update.status),
              percent: device.inflight_update.progress || 0
            })
          else
            acc
          end
        end)

      assign(socket, :progress, progress)
    end)
    |> noreply()
  end

  def handle_async(:update_device_list, {:exit, reason}, socket) do
    %{devices: devices, device_statuses: device_statuses} = socket.assigns

    message =
      "Live.Devices.Index.handle_async:update_device_list failed due to exit: #{inspect(reason)}"

    _ = Sentry.capture_message(message, result: :none)

    socket
    |> assign(:list_loading?, false)
    |> assign(:devices, AsyncResult.failed(devices, {:exit, reason}))
    |> assign(:device_statuses, AsyncResult.ok(device_statuses, {:exit, reason}))
    |> noreply()
  end

  def handle_async(:load_peek, {:ok, {id, data}}, %{assigns: %{peek_device_id: id}} = socket) do
    socket
    |> assign(:peek, AsyncResult.ok(data))
    |> noreply()
  end

  def handle_async(:load_peek, {:ok, _stale}, socket), do: noreply(socket)

  def handle_async(:load_peek, {:exit, reason}, socket) do
    socket
    |> assign(:peek, AsyncResult.failed(socket.assigns.peek, {:exit, reason}))
    |> noreply()
  end

  def handle_async(:update_filter_data, {:ok, new_assigns}, socket) do
    socket = assign(socket, new_assigns)

    socket
    |> assign(:filters_ready?, true)
    |> assign(:advanced_query_schema_json, advanced_query_schema_json(socket.assigns))
    |> assign_facets()
    |> noreply()
  end

  def handle_async(:load_facets, {:ok, {key, facets}}, socket) do
    if key == facets_key(socket.assigns) do
      socket
      |> assign(:facets, facets)
      |> noreply()
    else
      noreply(socket)
    end
  end

  def handle_async(:load_facets, {:exit, _reason}, socket), do: noreply(socket)

  def handle_async(:load_no_match_suggestions, {:ok, {key, suggestions}}, socket) do
    if key == socket.assigns.list_key do
      socket
      |> assign(:no_match_suggestions, suggestions)
      |> noreply()
    else
      noreply(socket)
    end
  end

  # Without the counts the empty list still says nothing matches; it just
  # can't say what would.
  def handle_async(:load_no_match_suggestions, {:exit, _reason}, socket) do
    socket
    |> assign(:no_match_suggestions, [])
    |> noreply()
  end

  def handle_async(:update_filter_data, {:exit, reason}, socket) do
    message =
      "Live.Devices.Index.handle_async:update_filter_data failed due to exit: #{inspect(reason)}"

    {:ok, _} = Sentry.capture_message(message, result: :none)

    socket
    |> assign(:filters_ready?, false)
    |> noreply()
  end

  def handle_async(:enable_updates_for_devices, {:ok, results}, socket) do
    socket
    |> put_flash(
      :info,
      "Enabled updates for #{number_to_delimited(results.ok, precision: 0)} selected device(s)."
    )
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(:disable_updates_for_devices, {:ok, results}, socket) do
    socket
    |> put_flash(
      :info,
      "Disabled updates for #{number_to_delimited(results.ok, precision: 0)} selected device(s)."
    )
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(:clear_penalty_box_for_devices, {:ok, results}, socket) do
    socket
    |> put_flash(
      :info,
      "#{number_to_delimited(results.ok, precision: 0)} selected device(s) cleared from the penalty box."
    )
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(bulk_action, {:ok, results}, socket) when bulk_action in @tag_bulk_actions do
    {applied, attempted} = tag_action_wording(bulk_action)

    case results do
      %{ok: successful_count, error: 0} ->
        put_flash(
          socket,
          :info,
          "#{applied} all selected devices (#{number_to_delimited(successful_count, precision: 0)})."
        )

      %{ok: 0, error: unsuccessful_count} ->
        put_flash(
          socket,
          :error,
          "#{attempted} failed for all selected devices (#{number_to_delimited(unsuccessful_count, precision: 0)})."
        )

      %{ok: successful_count, error: unsuccessful_count} ->
        put_flash(
          socket,
          :notice,
          "#{applied} #{number_to_delimited(successful_count, precision: 0)} devices, #{number_to_delimited(unsuccessful_count, precision: 0)} devices had errors."
        )
    end
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(:remove_many_from_deployment_group, {:ok, results}, socket) do
    case results do
      %{ok: successful_count, error: 0} ->
        put_flash(
          socket,
          :info,
          "All devices (#{number_to_delimited(successful_count, precision: 0)}) were successfully removed from their deployment group."
        )

      %{ok: 0, error: _} ->
        put_flash(
          socket,
          :error,
          "No devices were successfully removed from their deployment group."
        )

      %{ok: successful_count, error: unsuccessful_count} ->
        put_flash(
          socket,
          :notice,
          "#{number_to_delimited(successful_count, precision: 0)} devices were successfully from their deployment group, and #{number_to_delimited(unsuccessful_count, precision: 0)} devices had errors and couldn't be removed"
        )
    end
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(:move_many_to_deployment_group, {:ok, results}, socket) do
    case results do
      %{ok: _, error: 0} ->
        put_flash(socket, :info, "All selected devices were successfully assigned to the selected deployment group.")

      %{ok: 0, error: _} ->
        put_flash(socket, :error, "No devices were successfully assigned to the selected deployment group.")

      %{ok: successful_count, error: unsuccessful_count} ->
        put_flash(
          socket,
          :notice,
          "#{number_to_delimited(successful_count, precision: 0)} devices were successfully assigned to the selected deployment group, and #{number_to_delimited(unsuccessful_count, precision: 0)} devices encountered errors and couldn't be assigned."
        )
    end
    |> assign_display_devices()
    |> noreply()
  end

  def handle_async(:move_many, {:ok, results}, socket) do
    case results do
      %{ok: _, error: 0} ->
        put_flash(socket, :info, "All selected devices successfully moved to the selected product.")

      %{ok: 0, error: _} ->
        put_flash(socket, :error, "No devices were successfully moved to the selected product.")

      %{ok: successful_count, error: unsuccessful_count} ->
        put_flash(
          socket,
          :error,
          "#{number_to_delimited(successful_count, precision: 0)} devices were successfully moved to the selected product, and #{number_to_delimited(unsuccessful_count, precision: 0)} devices had errors and couldn't be moved"
        )
    end
    |> assign_display_devices()
    |> noreply()
  end

  # The chips plus a tag still being typed when the form was sent, which is
  # applied with them rather than quietly dropped.
  defp submitted_tags(params) do
    [Map.get(params, "tags", ""), Map.get(params, "new_tag", "")]
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp tag_operation(%{"tag_operation" => operation}) when operation in ~w(set add remove), do: operation
  defp tag_operation(_params), do: "set"

  defp tag_bulk_action("add"), do: :add_tags_to_devices
  defp tag_bulk_action("remove"), do: :remove_tags_from_devices
  defp tag_bulk_action("set"), do: :tag_devices

  # Dispatched by hand rather than through `apply/3`, so the compiler sees the
  # calls and a rename of one of them can't slip through.
  defp bulk_update_tags(:tag_devices, devices, user, tags) do
    BulkActions.tag_devices(devices, user, tags)
  end

  defp bulk_update_tags(:add_tags_to_devices, devices, user, tags) do
    BulkActions.add_tags_to_devices(devices, user, tags)
  end

  defp bulk_update_tags(:remove_tags_from_devices, devices, user, tags) do
    BulkActions.remove_tags_from_devices(devices, user, tags)
  end

  # `{what was applied, what was attempted}`, so one set of messages covers
  # setting, adding and removing tags.
  defp tag_action_wording(:tag_devices), do: {"Tags updated on", "Updating tags"}
  defp tag_action_wording(:add_tags_to_devices), do: {"Tags added to", "Adding tags"}
  defp tag_action_wording(:remove_tags_from_devices), do: {"Tags removed from", "Removing tags"}

  defp may_select_devices?(scope), do: Enum.any?(@bulk_action_permissions, &authorized?(&1, scope))

  defp may_select_devices!(scope) do
    if !may_select_devices?(scope), do: raise(NervesHubWeb.UnauthorizedError)
  end

  # The role in the target org was checked when the product was picked, and
  # may have changed since, so it is checked again before anything moves.
  defp still_allowed_target(_scope, nil), do: :no_product

  defp still_allowed_target(scope, target_product) do
    case Products.get_by_id(scope, target_product.id, :manage) do
      {:ok, product} -> {:ok, product}
      {:error, :not_found} -> :not_allowed
    end
  end

  defp refuse_target_product(socket) do
    socket
    |> assign(:target_product, nil)
    |> put_flash(:error, "Invalid product selection")
  end

  defp start_bulk_async(socket, name, args) do
    ecto_query = filter_query(socket)

    socket
    |> start_async(name, fn -> apply(BulkActions, name, [ecto_query | args]) end)
    |> put_flash(:notice, "Updating devices, please wait...")
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

  defp filter_query(%{assigns: %{current_scope: scope}} = socket) do
    opts = %{
      sort: {
        String.to_existing_atom(socket.assigns.sort_direction),
        String.to_existing_atom(socket.assigns.current_sort)
      },
      filters: DeviceFiltering.transform_deployment_filter(socket.assigns.current_filters)
    }

    Devices.filter_query(scope.product, scope.user, opts)
  end

  defp find_listed_device(%{assigns: %{devices: %AsyncResult{ok?: true, result: devices}}}, id) do
    case parse_id(id) do
      nil -> nil
      id -> Enum.find(devices, &(&1.id == id))
    end
  end

  defp find_listed_device(_socket, _id), do: nil

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_id(_id), do: nil

  # The list already has the device; the peek loads what the list doesn't
  # show. Each load carries its device's id, so a slow one that lands after
  # the peek has moved on is dropped.
  defp open_peek(%{assigns: %{peek_device_id: id}} = socket, %Device{id: id}), do: socket

  defp open_peek(socket, device) do
    socket
    |> assign(:peek_device_id, device.id)
    |> assign(:peek, AsyncResult.loading())
    |> start_async(:load_peek, fn ->
      {attempts, attempts_page} = UpdateHistory.device_attempts(device, 1, 5)
      {activity, _meta} = AuditLogs.logs_for_feed(device, %{page: 1, page_size: 3})

      {device.id,
       %{
         attempts: attempts,
         attempt_count: attempts_page.total_count,
         activity: activity,
         metrics: Metrics.get_latest_metric_set(device.id)
       }}
    end)
  end

  # Which list the loaded devices are, by what was asked for rather than what
  # came back, so a refresh of the same list keeps its key. The Needs
  # attention list opens its first device in the peek when this changes.
  defp list_key(%{
         current_filters: filters,
         paginate_opts: paginate_opts,
         current_sort: sort,
         sort_direction: direction
       }) do
    :erlang.phash2({filters, paginate_opts.page_number, paginate_opts.page_size, sort, direction})
  end

  # On the Needs attention tab, wide screens dock the peek beside the list,
  # which makes room for it, rather than laying it over the list.
  defp peek_docked?(%{state: "attention"}, devices, id), do: not is_nil(peek_device(devices, id))
  defp peek_docked?(_filters, _devices, _id), do: false

  defp peek_device(_devices, nil), do: nil
  defp peek_device(%AsyncResult{ok?: true, result: devices}, id), do: Enum.find(devices, &(&1.id == id))
  defp peek_device(_devices, _id), do: nil

  defp update_device_statuses(socket, device_id, status) do
    updated_statuses = Map.replace(socket.assigns.device_statuses.result, device_id, status)

    assign(socket, :device_statuses, AsyncResult.ok(updated_statuses))
  end

  defp update_firmware_progress(%{assigns: %{progress: progress}} = socket, device_id) do
    %Device{id: device_id}
    |> FirmwareUpdates.inflight_update_for()
    |> case do
      nil -> Map.delete(progress, device_id)
      ifu -> Map.put(progress, device_id, %{stage: ifu.status, percent: ifu.progress})
    end
    |> then(fn progresses ->
      assign(socket, :progress, progresses)
    end)
  end

  defp maybe_pluralize(count, to_pluralize) do
    if count == 1 do
      to_pluralize
    else
      to_pluralize <> "s"
    end
  end

  # "online", or for a device that is not, whether it is asleep or overdue.
  defp device_status(device) do
    case Tracker.connection_status(device) do
      "online" -> "online"
      _offline -> DeviceSleep.list_status(device.latest_connection)
    end
  end

  # The listed device's connection, closed as the broadcast describes it, so
  # its row, Connection column and side panel say when a sleeping device is
  # due back without waiting for the next refresh. Details a broadcast from
  # an older node leaves out stay as they were.
  defp close_listed_connection(%{assigns: %{devices: %AsyncResult{ok?: true} = devices}} = socket, device_id, payload) do
    changes =
      payload
      |> Map.take([:disconnected_reason, :disconnected_at, :expected_wake_at])
      |> Map.put(:status, :disconnected)

    listed =
      Enum.map(devices.result, fn
        %Device{id: ^device_id, latest_connection: %DeviceConnection{} = connection} = device ->
          %{device | latest_connection: struct(connection, changes)}

        device ->
          device
      end)

    assign(socket, :devices, %{devices | result: listed})
  end

  defp close_listed_connection(socket, _device_id, _payload), do: socket

  # The connection that just ended, as `Tracker.offline/1` describes it. A
  # broadcast from a node that does not send the details reads as offline.
  defp offline_status(payload) do
    DeviceSleep.list_status(%DeviceConnection{
      status: :disconnected,
      disconnected_reason: payload[:disconnected_reason],
      disconnected_at: payload[:disconnected_at],
      expected_wake_at: payload[:expected_wake_at]
    })
  end

  defp pagination_changes(params) do
    Ecto.Changeset.cast(
      {@default_pagination, @pagination_types},
      params,
      Map.keys(@default_pagination)
    ).changes
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
    JS.show(js, transition: "fade-in", to: "##{id}")
  end

  def hide_menu(id, js \\ %JS{}) do
    JS.hide(js, transition: "fade-out", to: "##{id}")
  end

  defp maybe_assign_available_deployment_groups_for_filtered_platform(
         %{assigns: %{current_scope: scope, current_filters: %{platform: platform}}} = socket
       )
       when platform != "" do
    socket
    |> assign(
      :available_deployment_groups_for_filtered_platform,
      ManagedDeployments.get_by_product_and_platform(scope.product, platform)
    )
    |> assign(
      :available_firmwares_for_filtered_platform,
      Firmwares.get_firmwares_by_product_and_platform(scope.product, platform)
    )
  end

  defp maybe_assign_available_deployment_groups_for_filtered_platform(socket) do
    socket
    |> assign(:available_deployment_groups_for_filtered_platform, [])
    |> assign(:available_firmwares_for_filtered_platform, [])
  end

  # The tabs, search and buttons around the list: there while it first
  # loads, so they don't move in above it when it arrives, and after it while
  # it has devices, a filter is what emptied it, or the product has devices
  # this page doesn't (one past the last).
  defp list_chrome?(%AsyncResult{loading: loading} = device_async, currently_filtering?, product_device_count),
    do:
      not is_nil(loading) or has_results?(device_async, currently_filtering?) or
        (device_async.ok? and is_integer(product_device_count) and product_device_count > 0)

  # The columns the table shows, in its order.
  defp visible_columns(user), do: Enum.filter(DeviceColumns.columns(), &show_column?(user, &1))

  defp has_results?(%AsyncResult{} = device_async, currently_filtering?) do
    device_async.ok? && (Enum.any?(device_async.result) || currently_filtering?)
  end

  defp update_selected_device_info(%{assigns: %{selected_devices: []}} = socket) do
    socket
    |> assign(:bulk_menu, nil)
    |> assign(:selected_shared_deployment_group, nil)
    |> assign(:selected_have_deployment_groups, false)
    |> assign(:valid_deployment_groups_for_selected, [])
    |> assign(:target_deployment_group, nil)
  end

  defp update_selected_device_info(
         %{assigns: %{selected_devices: selected_ids, devices: devices, product: product}} = socket
       ) do
    selected =
      if devices.ok? do
        Enum.filter(devices.result, &(&1.id in selected_ids))
      else
        []
      end

    # Determine deployment group info for "Remove from DG" section
    deployment_ids =
      selected
      |> Enum.map(& &1.deployment_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    has_deployment_groups = Enum.any?(deployment_ids)

    shared_deployment_group =
      case deployment_ids do
        [single_id] ->
          Enum.find(socket.assigns.deployment_groups, &(&1.id == single_id))

        _ ->
          nil
      end

    # Determine valid deployment groups for "Set DG" section
    # Only show DGs when all selected devices share a single platform,
    # to prevent partially setting a deployment group.
    platforms =
      selected
      |> Enum.map(fn d -> d.firmware_metadata && d.firmware_metadata.platform end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    valid_dgs =
      case platforms do
        [_single_platform] -> ManagedDeployments.get_by_product_and_platforms(product, platforms)
        _ -> []
      end

    socket
    |> assign(:selected_shared_deployment_group, shared_deployment_group)
    |> assign(:selected_have_deployment_groups, has_deployment_groups)
    |> assign(:valid_deployment_groups_for_selected, valid_dgs)
    |> assign(:target_deployment_group, nil)
  end

  # A refresh usually returns the page it already had, so only the devices that
  # came or went change hands. Re-subscribing to the whole page each time cost
  # two registry writes per device for a set that had not moved.
  #
  # The subscribed ids are tracked here rather than read back off `:devices`,
  # which is an `AsyncResult` the display code resets on its own schedule.
  defp sync_device_subscriptions(socket, devices) do
    subscribed = socket.assigns.subscribed_device_ids

    # The device the Add device dialog is waiting on, even off this page.
    wanted =
      case socket.assigns.added_device_id do
        nil -> MapSet.new(devices, & &1.id)
        id -> devices |> MapSet.new(& &1.id) |> MapSet.put(id)
      end

    Enum.each(MapSet.difference(subscribed, wanted), fn device_id ->
      PubSub.unsubscribe(device_id)
    end)

    Enum.each(MapSet.difference(wanted, subscribed), fn device_id ->
      PubSub.subscribe(device_id)
    end)

    assign(socket, :subscribed_device_ids, wanted)
  end

  defp safe_refresh(socket) do
    if is_nil(socket.assigns.live_refresh_timer) and socket.assigns.visible? do
      # Nothing pending, we perform a refresh
      socket
      |> assign_display_devices()
      |> assign(:live_refresh_timer, Process.send_after(self(), :live_refresh, @refresh_delay))
    else
      # a timer is already pending, we flag the pending request
      assign(socket, :live_refresh_pending?, true)
    end
  end

  defp parse_device_id(topic) do
    "internal:device:" <> device_id = topic
    String.to_integer(device_id)
  end

  # A column the user switched off still renders its cell, for the card a row
  # becomes on a phone, but not from sm up.
  defp column_class(user, column), do: if(!show_column?(user, column), do: "sm:hidden")

  # "1–25 of 1,240", above the cards on a phone.
  defp page_range(%{total_count: 0}), do: "No devices"

  defp page_range(%{current_page: page, page_size: size, total_count: total}) do
    first = (page - 1) * size + 1
    last = min(page * size, total)

    "#{delimit(first)}–#{delimit(last)} of #{delimit(total)}"
  end

  defp page_range(_pager), do: nil

  defp delimit(number), do: Number.Delimit.number_to_delimited(number, precision: 0)

  # The phone's sort menu, `{label, "field:direction"}`.
  defp phone_sort_options() do
    [
      {"Sort: Identifier A–Z", "identifier:asc"},
      {"Sort: Identifier Z–A", "identifier:desc"},
      {"Sort: Connected most recently", "connection_established_at:asc"},
      {"Sort: Connected longest ago", "connection_established_at:desc"},
      {"Sort: Tags A–Z", "tags:asc"},
      {"Sort: Tags Z–A", "tags:desc"}
    ]
  end

  # A row checkbox's label, which fills its cell so a click near the box
  # selects the row rather than opening the device. The input is visually
  # hidden, and the box inside the label stands in for it, focus ring included.
  defp checkbox_classes() do
    [
      "flex w-10 cursor-pointer items-center pl-4 peer-disabled:cursor-not-allowed peer-disabled:opacity-40",
      "[&>.checkbox-box]:flex [&>.checkbox-box]:size-3.5 [&>.checkbox-box]:items-center [&>.checkbox-box]:justify-center",
      "[&>.checkbox-box]:rounded-xs [&>.checkbox-box]:border [&>.checkbox-box]:border-line-control [&>.checkbox-box]:bg-surface-raised",
      "peer-checked:[&>.checkbox-box]:border-primary peer-checked:[&>.checkbox-box]:bg-primary",
      "peer-focus-visible:[&>.checkbox-box]:outline-2 peer-focus-visible:[&>.checkbox-box]:outline-offset-2",
      "peer-focus-visible:[&>.checkbox-box]:outline-focus-ring"
    ]
  end

  # The filters a Filters panel token's × resets: a metric's key, comparison
  # and value go together.
  defp filter_removal(:metrics_key), do: Map.take(@default_filters, [:metrics_key, :metrics_operator, :metrics_value])
  defp filter_removal(key), do: %{key => Map.fetch!(@default_filters, key)}

  # When filters, or the query, leave a list empty, counts what removing each
  # one would bring back into the selected tab, for the empty list to offer.
  defp assign_no_match_suggestions(%{assigns: %{current_filters: filters}} = socket, []) do
    removable = no_match_removable(filters)

    if removable == [] do
      assign(socket, :no_match_suggestions, nil)
    else
      %{current_scope: scope, list_key: key, deployment_groups: groups, signer_cas: signer_cas} = socket.assigns

      socket
      |> assign(:no_match_suggestions, nil)
      |> start_async(:load_no_match_suggestions, fn ->
        suggestions =
          removable
          |> Enum.map(fn removed ->
            without = Map.merge(filters, filter_removal(removed))
            opts = %{filters: DeviceFiltering.transform_deployment_filter(without)}
            counts = Devices.state_counts(scope.product, scope.user, opts)

            %{
              key: removed,
              text: no_match_text(removed, filters, groups, signer_cas),
              count: counts[tab_count_key(filters)] || 0
            }
          end)
          |> Enum.sort_by(& &1.count, :desc)

        {key, suggestions}
      end)
    end
  end

  defp assign_no_match_suggestions(socket, _devices), do: assign(socket, :no_match_suggestions, nil)

  # The Filters panel's filters and the query, whichever are narrowing the list.
  defp no_match_removable(filters) do
    DeviceFilters.applied(filters) ++ if(filters.advanced_query in [nil, ""], do: [], else: [:advanced_query])
  end

  defp no_match_text(:advanced_query, _filters, _groups, _signer_cas), do: "search"
  defp no_match_text(key, filters, groups, signer_cas), do: DeviceFilters.token_text(key, filters, groups, signer_cas)

  # Which of `Devices.state_counts/3` the selected tab (or reason) shows.
  defp tab_count_key(%{state: "attention", reason: reason}) when reason != "", do: reason
  defp tab_count_key(%{state: ""}), do: "all"
  defp tab_count_key(%{state: state}), do: state

  # With no devices yet, the list looks for the first one every few seconds,
  # as the onboarding says it will, rather than every minute.
  defp await_first_device(socket, 0) do
    if socket.assigns.awaiting_first_device? or not connected?(socket) do
      socket
    else
      Process.send_after(self(), :await_first_device, @first_device_check_time)
      assign(socket, :awaiting_first_device?, true)
    end
  end

  defp await_first_device(socket, _count), do: socket

  # A tab (or one of its reasons) with nothing in it, as opposed to filters
  # that match nothing.
  defp only_state_filtered?(filters) do
    Map.drop(filters, [:state, :reason]) == Map.drop(@default_filters, [:state, :reason])
  end

  defp empty_tab_title(%{state: "attention", reason: "unhealthy"}), do: "No devices are unhealthy"
  defp empty_tab_title(%{state: "attention", reason: "failing"}), do: "No devices are failing updates"
  defp empty_tab_title(%{state: "attention", reason: "not_seen"}), do: "Every device has been seen lately"
  defp empty_tab_title(%{state: state}), do: empty_tab_title(state)
  defp empty_tab_title("attention"), do: "Nothing needs attention"
  defp empty_tab_title("online"), do: "No devices are online"
  defp empty_tab_title("updating"), do: "No devices are updating"
  defp empty_tab_title("offline"), do: "Every device is online"

  defp empty_tab_detail(%{state: "attention", reason: "unhealthy"}),
    do: "Devices show here when their health is unhealthy."

  defp empty_tab_detail(%{state: "attention", reason: "failing"}),
    do: "Devices show here when their updates are on hold after repeated failures."

  defp empty_tab_detail(%{state: "attention", reason: "not_seen"}),
    do: "Devices show here when they go #{DeviceFiltering.not_seen_days()} days unseen."

  defp empty_tab_detail(%{state: state}), do: empty_tab_detail(state)

  defp empty_tab_detail("attention"),
    do:
      "Every device is healthy, no update is failing, and all were seen in the last #{DeviceFiltering.not_seen_days()} days."

  defp empty_tab_detail("online"), do: "Devices show here while they're connected."
  defp empty_tab_detail("updating"), do: "Devices show here while they install an update."
  defp empty_tab_detail("offline"), do: "Devices show here when they disconnect."

  # How many filters the Filters panel has applied, for the count on its button.
  defp filter_count(filters), do: length(DeviceFilters.applied(filters))

  # "2 devices", or "2 of 40 devices" when filters or a tab leave some out.
  defp device_count_suffix(shown, total) when is_integer(total) and shown < total,
    do: " of #{number_to_delimited(total, precision: 0)} devices"

  defp device_count_suffix(1, _total), do: " device"
  defp device_count_suffix(_shown, _total), do: " devices"

  # Saved to the user's display preferences, so every product's devices list
  # shows the same columns.
  defp save_columns(%{assigns: %{current_scope: scope}} = socket, columns) do
    {:ok, user} =
      Accounts.update_user_default_columns(scope.user, :device_list_columns, Enum.map(columns, &to_string/1))

    assign(socket, :current_scope, %{scope | user: user})
  end

  defp show_column?(user, column) do
    ListSettingsSidebar.show_column?(user.display_preferences, :device_list_columns, column)
  end

  # The shared secret the onboarding fills in, or why there isn't one. The
  # secret lets a device connect and register itself, so only members who
  # could manage it are shown it.
  defp onboarding_secret(product, scope) do
    active = Enum.find(product.shared_secret_auths, &is_nil(&1.deactivated_at))

    cond do
      is_nil(active) -> {nil, :none}
      authorized?(:"product:update", scope) -> {active, nil}
      true -> {nil, :hidden}
    end
  end

  # Dims a list while a different one loads (`list_loading?`), after a
  # moment so a quick load doesn't flash; it comes back at once.
  defp loading_dim(true), do: "opacity-50 transition-opacity delay-200 duration-150"
  defp loading_dim(false), do: "transition-opacity duration-150"

  defp onboarding_nhl_host() do
    Application.get_env(:nerves_hub, :devices_websocket_url) || URI.parse(NervesHubWeb.Endpoint.url()).host
  end
end
