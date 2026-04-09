defmodule NervesHubWeb.Live.Devices.Index do
  use NervesHubWeb, :live_view

  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Metrics
  alias NervesHub.Firmwares
  alias NervesHub.ManagedDeployments
  alias NervesHub.Products
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.FilterSidebar
  alias NervesHubWeb.Components.HealthStatus
  alias NervesHubWeb.Components.Pager
  alias NervesHubWeb.Components.Sorting
  alias NervesHubWeb.LayoutView.DateTimeFormat
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS
  alias Phoenix.Socket.Broadcast

  require OpenTelemetry.Tracer, as: Tracer

  @list_refresh_time 10_000
  # Delay frequent refresh triggers to this interval
  @refresh_delay 1000

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
    |> assign(:firmware_versions, firmware_versions(product.id))
    |> assign(:platforms, [])
    |> assign(:show_filters, false)
    |> assign(:current_filters, @default_filters)
    |> assign(:currently_filtering, false)
    |> assign(:selected_devices, [])
    |> assign(:target_product, nil)
    |> assign(:progress, %{})
    |> assign(:valid_tags, true)
    |> assign(:device_tags, "")
    |> assign(:total_entries, 0)
    |> assign(:visible?, true)
    |> assign(:live_refresh_timer, nil)
    |> assign(:live_refresh_pending?, false)
    |> assign(:received_connection_change_identifiers, %{})
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
    |> assign_filter_data()
    |> noreply()
  end

  defp self_path(%{assigns: %{current_scope: scope}} = socket, extra) do
    params = Enum.into(stringify_keys(extra), socket.assigns.params)
    pagination = pagination_changes(params)
    filter = filter_changes(params)
    sort = sort_changes(params)

    query =
      filter
      |> Map.merge(pagination)
      |> Map.merge(sort)

    ~p"/org/#{scope.org}/#{scope.product}/devices?#{query}"
  end

  defp subscribe_and_refresh_device_list_timer(socket) do
    if connected?(socket) do
      socket.endpoint.subscribe("product:#{socket.assigns.current_scope.product.id}:devices")
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

  @decorate requires_permission(:"device:update")
  def handle_event("select", %{"id" => id_str}, socket) do
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
      |> update_selected_device_info()
      |> noreply()
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid device selection")}
    end
  end

  @decorate requires_permission(:"device:update")
  def handle_event("select-all", _, socket) do
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

  @decorate requires_permission(:"device:update")
  def handle_event("deselect-all", _, socket) do
    socket
    |> assign(%{selected_devices: [], available_deployment_groups_for_filtered_platform: []})
    |> update_selected_device_info()
    |> noreply()
  end

  def handle_event("validate-tags", %{"tags" => tags}, socket) do
    if String.contains?(tags, " ") do
      {:noreply, assign(socket, valid_tags: false, device_tags: tags)}
    else
      {:noreply, assign(socket, valid_tags: true, device_tags: tags)}
    end
  end

  @decorate requires_permission(:"device:update")
  def handle_event("tag-devices", %{"tags" => tags}, socket) do
    %{selected_devices: selected_devices, current_scope: scope} = socket.assigns

    with {:devices, devices} when is_list(devices) and devices != [] <-
           {:devices, Devices.get_devices_by_id(scope, selected_devices)},
         result = Devices.tag_devices(devices, scope.user, tags),
         {:successful, true} <- {:successful, Enum.any?(result[:ok])},
         {:has_errors, false, _result} <- {:has_errors, Enum.any?(result[:error]), result} do
      socket
      |> put_flash(:info, "Tagged all selected device(s).")
      |> assign_display_devices()
      |> noreply()
    else
      {:devices, _} ->
        {:noreply, put_flash(socket, :error, "You haven't selected any devices")}

      {:successful, false} ->
        {:noreply, put_flash(socket, :error, "No devices were successfully tagged")}

      {:has_errors, true, result} ->
        socket
        |> put_flash(
          :info,
          "#{Enum.count(result[:ok])} devices were successfully tagged and #{Enum.count(result[:error])} devices had errors."
        )
        |> assign(selected_devices: Enum.map(result[:ok], & &1.id))
        |> assign_display_devices()
        |> noreply()
    end
  end

  def handle_event("target-product", %{"product_id" => ""}, socket) do
    {:noreply, assign(socket, target_product: nil)}
  end

  @decorate requires_permission(:"device:update")
  def handle_event("target-product", %{"product_id" => pid_str}, socket) do
    with {product_id, ""} <- Integer.parse(pid_str),
         {:ok, product} <- Products.get_by_id(socket.assigns.current_scope, product_id) do
      {:noreply, assign(socket, target_product: product)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid product selection")}
    end
  end

  def handle_event("target-deployment-group", params, socket) when not is_map_key(params, "deployment_group") do
    {:noreply, assign(socket, target_deployment_group: nil)}
  end

  def handle_event("target-deployment-group", %{"deployment_group" => ""}, socket) do
    {:noreply, assign(socket, target_deployment_group: nil)}
  end

  @decorate requires_permission(:"device:update")
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
    %{
      selected_devices: selected_devices,
      target_product: target_product,
      current_scope: scope
    } = socket.assigns

    with {:devices_selected, true} <- {:devices_selected, selected_devices != []},
         {:product_selected, true} <- {:product_selected, target_product != nil},
         devices when is_list(devices) and devices != [] <- Devices.get_devices_by_id(scope, selected_devices),
         result = Devices.move_many(scope, devices, target_product),
         {:successful, true} <- {:successful, Enum.any?(result[:ok])},
         {:has_errors, false, _result} <- {:has_errors, Enum.any?(result[:error]), result} do
      socket
      |> assign(:target_product, nil)
      |> assign_display_devices()
      |> put_flash(:info, "All selected devices successfully moved moved to #{target_product.name}")
      |> noreply()
    else
      {:devices_selected, false} ->
        {:noreply, put_flash(socket, :error, "You haven't selected any devices")}

      {:product_selected, false} ->
        {:noreply, put_flash(socket, :error, "You haven't selected a product")}

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

  @decorate requires_permission(:"device:update")
  def handle_event("move-devices-deployment-group", _, socket) do
    %{
      assigns: %{
        current_scope: scope,
        selected_devices: selected_devices,
        target_deployment_group: target_deployment_group
      }
    } = socket

    with {:ok, %{updated: updated_count, ignored: ignored_count} = result} <-
           Devices.move_many_to_deployment_group(scope, selected_devices, target_deployment_group.id),
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

  def handle_event("target-firmware", %{"firmware" => ""}, socket) do
    {:noreply, assign(socket, target_firmware: nil)}
  end

  @decorate requires_permission(:"device:update")
  def handle_event("target-firmware", %{"firmware" => firmware_uuid}, socket) do
    firmware =
      Enum.find(
        socket.assigns.available_firmwares_for_filtered_platform,
        &(&1.uuid == firmware_uuid)
      )

    {:noreply, assign(socket, target_firmware: firmware)}
  end

  @decorate requires_permission(:"device:update")
  def handle_event("push-firmware-to-devices", _, socket) do
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

  @decorate requires_permission(:"device:update")
  def handle_event("remove-devices-from-deployment-group", _, socket) do
    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    {:ok, count} = Devices.remove_many_from_deployment_group(scope, selected_devices)

    socket
    |> assign_display_devices()
    |> put_flash(:info, "#{count} device(s) removed from their deployment group.")
    |> noreply()
  end

  @decorate requires_permission(:"device:update")
  def handle_event("disable-updates-for-devices", _, socket) do
    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    %{ok: successfuls} =
      Devices.get_devices_by_id(scope, selected_devices)
      |> Devices.disable_updates_for_devices(scope.user)

    socket
    |> assign(selected_devices: selected_devices)
    |> put_flash(:info, "Disabled updates for #{Enum.count(successfuls)} selected device(s).")
    |> assign_display_devices()
    |> noreply()
  end

  @decorate requires_permission(:"device:update")
  def handle_event("enable-updates-for-devices", _, socket) do
    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    %{ok: successfuls} =
      Devices.get_devices_by_id(scope, selected_devices)
      |> Devices.enable_updates_for_devices(scope.user)

    socket
    |> assign(selected_devices: selected_devices)
    |> put_flash(:info, "Enabled updates for #{Enum.count(successfuls)} selected device(s).")
    |> assign_display_devices()
    |> noreply()
  end

  @decorate requires_permission(:"device:update")
  def handle_event("clear-penalty-box-for-devices", _, socket) do
    %{assigns: %{current_scope: scope, selected_devices: selected_devices}} = socket

    %{ok: successfuls} =
      Devices.get_devices_by_id(scope, selected_devices)
      |> Devices.clear_penalty_box_for_devices(scope.user)

    socket
    |> assign(selected_devices: selected_devices)
    |> put_flash(
      :info,
      "#{Enum.count(successfuls)} selected device(s) cleared from the penalty box."
    )
    |> assign_display_devices()
    |> noreply()
  end

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

  def handle_info(%Broadcast{event: "connection:status", payload: payload}, socket) do
    socket
    |> assign(
      :received_connection_change_identifiers,
      Map.put(socket.assigns.received_connection_change_identifiers, payload.device_id, payload)
    )
    |> safe_refresh()
    |> update_device_statuses(payload)
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    socket
    |> assign(
      :received_connection_change_identifiers,
      Map.put(socket.assigns.received_connection_change_identifiers, payload.device_id, payload)
    )
    |> safe_refresh()
    |> update_device_statuses(payload)
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: %{device_id: device_id, percent: percent}}, socket)
      when percent > 99 do
    socket
    |> assign(:progress, Map.delete(socket.assigns.progress, device_id))
    |> safe_refresh()
    |> noreply()
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: %{device_id: device_id, percent: percent}}, socket) do
    socket
    |> assign(:progress, Map.put(socket.assigns.progress, device_id, percent))
    |> safe_refresh()
    |> noreply()
  end

  # Unknown broadcasts get ignored, likely from the device:id:internal channel
  def handle_info(%Broadcast{}, socket) do
    socket
    |> safe_refresh()
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

  def handle_info(:live_refresh, socket) do
    if socket.assigns.visible? and socket.assigns.live_refresh_pending? do
      Tracer.with_span "NervesHubWeb.Live.Devices.Index.live_refresh_device_list" do
        socket
        |> assign_display_devices()
      end
    else
      socket
    end
    |> assign(:live_refresh_timer, nil)
    |> assign(:live_refresh_pending?, false)
    |> noreply()
  end

  defp assign_filter_data(%{assigns: %{current_scope: %{product: product}}} = socket) do
    socket
    |> start_async(:update_filter_data, fn ->
      [
        current_alarms: Alarms.get_current_alarm_types(product.id),
        metrics_keys: Metrics.default_metrics(),
        deployment_groups: ManagedDeployments.get_deployment_groups_by_product(product),
        platforms: Devices.platforms(product.id)
      ]
    end)
  end

  defp assign_display_devices(%{assigns: %{current_scope: scope, paginate_opts: paginate_opts}} = socket) do
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
    |> start_async(:update_device_list, fn -> Devices.filter(scope.product, scope.user, opts) end)
  end

  def handle_async(:update_device_list, {:ok, {updated_devices, pager}}, socket) do
    %{devices: old_devices, device_statuses: old_device_statuses, paginate_opts: paginate_opts} =
      socket.assigns

    Enum.each(
      old_devices.result || [],
      fn device -> socket.endpoint.unsubscribe("device:#{device.identifier}:internal") end
    )

    updated_device_statuses =
      Map.new(updated_devices, fn device ->
        socket.endpoint.subscribe("device:#{device.identifier}:internal")

        payload = socket.assigns.received_connection_change_identifiers[device.identifier]

        if payload do
          {payload.device_id, payload.status}
        else
          {device.identifier, Tracker.connection_status(device)}
        end
      end)

    socket
    |> assign(:devices, AsyncResult.ok(old_devices, updated_devices))
    |> assign(:device_statuses, AsyncResult.ok(old_device_statuses, updated_device_statuses))
    |> assign(:received_connection_change_identifiers, %{})
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

  def handle_async(:update_filter_data, {:ok, new_assigns}, socket) do
    socket
    |> assign(new_assigns)
    |> assign(:filters_ready?, true)
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

  defp firmware_versions(product_id) do
    Firmwares.get_firmware_versions_by_product(product_id)
  end

  defp maybe_pluralize(count, to_pluralize) do
    if count == 1 do
      to_pluralize
    else
      to_pluralize <> "s"
    end
  end

  #
  # MOVE TO COMPONENTS
  #

  defp target_selected?(%{name: name}, value) when name == value, do: [selected: true]
  defp target_selected?(_, _), do: []

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

  defp has_results?(%AsyncResult{} = device_async, currently_filtering?) do
    device_async.ok? && (Enum.any?(device_async.result) || currently_filtering?)
  end

  defp update_selected_device_info(%{assigns: %{selected_devices: []}} = socket) do
    socket
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

  defp safe_refresh(socket) do
    if is_nil(socket.assigns.live_refresh_timer) and socket.assigns.visible? do
      # Nothing pending, we perform a refresh
      socket
      |> assign_display_devices()
      |> assign(:live_refresh_timer, Process.send_after(self(), :live_refresh, @refresh_delay))
    else
      # a timer is already pending, we flag the pending request
      socket
      |> assign(:live_refresh_pending?, true)
    end
  end

  defp onboarding_nhl_host() do
    Application.get_env(:nerves_hub, :devices_websocket_url) || URI.parse(NervesHubWeb.Endpoint.url()).host
  end
end
