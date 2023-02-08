defmodule NervesHubWWWWeb.DeviceLive.Index do
  use NervesHubWWWWeb, :live_view

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.{Accounts, Devices, Firmwares, Products, Products.Product}
  alias NervesHubWWWWeb.DeviceView

  alias Phoenix.Socket.Broadcast

  @default_filters %{
    "connection" => "",
    "firmware_version" => "",
    "healthy" => "",
    "id" => "",
    "tag" => ""
  }

  @default_page 1
  @default_page_size 25
  @default_page_sizes [25, 50, 75]

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

    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign(:current_sort, "identifier")
      |> assign(:sort_direction, :asc)
      |> assign(:paginate_opts, %{
        page_number: @default_page,
        page_size: @default_page_size,
        page_sizes: @default_page_sizes,
        total_pages: 0
      })
      |> assign(:firmware_versions, firmware_versions(product_id))
      |> assign(:show_filters, false)
      |> assign(:current_filters, @default_filters)
      |> assign(:currently_filtering, false)
      |> assign(:page_size_valid, true)
      |> assign(:selected_devices, [])
      |> assign(:target_product, nil)
      |> assign(:bulk_tagging, false)
      |> assign(:valid_tags, true)
      |> assign_display_devices()

    {:ok, socket}
  rescue
    e ->
      socket_error(socket, live_view_error(e))
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

  def handle_event("validate-paginate-opts", %{"page-size" => page_size}, socket) do
    socket =
      case Integer.parse(page_size) do
        {_, _} ->
          socket
          |> assign(:page_size_valid, true)

        :error ->
          socket
          |> assign(:page_size_valid, false)
      end

    {:noreply, socket}
  end

  def handle_event(
        "set-paginate-opts",
        %{"page-size" => page_size},
        %{
          assigns: %{
            paginate_opts:
              %{page_size: current_size, page_number: current_page_number} = paginate_opts
          }
        } = socket
      ) do
    socket =
      case Integer.parse(page_size) do
        {^current_size, _} ->
          socket

        {page_size, _} ->
          start_idx = current_size * (current_page_number - 1)
          page_number = floor(start_idx / page_size) + 1

          socket
          |> assign(:paginate_opts, %{
            paginate_opts
            | page_size: page_size,
              page_number: page_number
          })
          |> assign(:page_size_valid, true)
          |> assign_display_devices()

        :error ->
          socket
          |> assign(:page_size_valid, false)
      end

    {:noreply, socket}
  end

  def handle_event("toggle-filters", %{"toggle" => toggle}, socket) do
    socket =
      socket
      |> assign(:show_filters, toggle != "true")

    {:noreply, socket}
  end

  def handle_event("toggle-tags", %{"toggle" => toggle}, socket) do
    socket =
      socket
      |> assign(:bulk_tagging, toggle != "true")

    {:noreply, socket}
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

  def handle_event(
        "reboot",
        %{"device-id" => device_id},
        %{assigns: %{devices: devices, user: user}} = socket
      ) do
    user = Repo.preload(user, :org_users)

    device_id = String.to_integer(device_id)
    device_index = Enum.find_index(devices, fn device -> device.id == device_id end)
    device = Enum.at(devices, device_index)

    case Enum.find(user.org_users, &(&1.org_id == device.org_id)) do
      %{role: :admin} -> do_reboot(socket, :allowed, device, device_index)
      _ -> do_reboot(socket, :blocked, device, device_index)
    end
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
      {:noreply, assign(socket, valid_tags: false)}
    else
      {:noreply, assign(socket, valid_tags: true)}
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

  def handle_event("quarantine-devices", _, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.quarantine_devices(socket.assigns.user)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event("unquarantine-devices", _, socket) do
    %{ok: _successfuls} =
      Devices.get_devices_by_id(socket.assigns.selected_devices)
      |> Devices.unquarantine_devices(socket.assigns.user)

    socket =
      assign(socket, selected_devices: socket.assigns.selected_devices)
      |> assign_display_devices()

    {:noreply, socket}
  end

  def handle_event(
        "toggle_health_state",
        %{"device-id" => device_id},
        %{assigns: %{devices: devices, user: user}} = socket
      ) do
    device = Devices.get_device(device_id)

    params = %{healthy: !device.healthy}

    socket =
      case Devices.update_device(device, params) do
        {:ok, updated_device} ->
          AuditLogs.audit!(user, device, :update, params)

          devices =
            Enum.map(devices, fn
              device when device.id == updated_device.id ->
                meta = Map.take(device, Presence.__fields__())
                Map.merge(updated_device, meta)

              device ->
                device
            end)

          assign(socket, :devices, devices)

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to mark health state")
      end

    {:noreply, socket}
  end

  # Only sync devices currently on display
  def handle_info(%Broadcast{event: "connection_change", payload: payload}, socket) do
    {:noreply, assign(socket, devices: sync_devices(socket.assigns.devices, payload))}
  end

  defp assign_statuses(org_id, product_id, opts) do
    Devices.get_devices_by_org_id_and_product_id(org_id, product_id, opts)
    |> Map.update(:entries, [], &sync_devices/1)
  end

  defp sync_devices(devices, payload \\ %{}) do
    Enum.map(devices, fn device ->
      meta = Presence.find(device)

      case is_nil(meta) do
        true ->
          Map.put(device, :status, "offline")

        false ->
          fields = [
            :firmware_metadata,
            :last_communication,
            :status,
            :fwup_progress,
            :console_available
          ]

          device = Map.merge(device, Map.take(meta, fields))

          if Map.get(payload, :device_id) == device.id do
            payload = Map.delete(payload, :device_id)
            Map.merge(device, payload)
          else
            device
          end
      end
    end)
  end

  defp do_reboot(socket, :allowed, device, device_index) do
    AuditLogs.audit!(socket.assigns.user, device, :update, %{reboot: true})

    socket.endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

    devices =
      List.replace_at(socket.assigns.devices, device_index, %{device | status: "reboot-requested"})

    socket =
      socket
      |> put_flash(:info, "Device Reboot Requested")
      |> assign(:devices, devices)

    {:noreply, socket}
  end

  defp do_reboot(socket, :blocked, device, device_index) do
    msg = "User not authorized to reboot this device"

    AuditLogs.audit!(socket.assigns.user, device, :update, %{
      reboot: false,
      message: msg
    })

    devices =
      List.replace_at(socket.assigns.devices, device_index, %{device | status: "reboot-blocked"})

    socket =
      socket
      |> put_flash(:error, msg)
      |> assign(:devices, devices)

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

    page = assign_statuses(org.id, product.id, opts)
    assign_display_devices(socket, page)
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
    Firmwares.get_firmwares_by_product(product_id) |> Enum.map(& &1.version)
  end
end
