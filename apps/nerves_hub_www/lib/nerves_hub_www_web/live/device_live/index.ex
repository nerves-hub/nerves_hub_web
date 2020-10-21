defmodule NervesHubWWWWeb.DeviceLive.Index do
  use NervesHubWWWWeb, :live_view

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.{Accounts, Devices, Firmwares, Products}
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

  # def handle_params(%{"org_name"}, _url, socket) do
  #   IO.puts "Params: #{inspect params}"
  #   socket =
  #     socket
  #     # |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
  #     # |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
  #     # |> assign_new(:product, fn -> Products.get_product!(product_id) end)
  #   {:noreply, socket}
  # end/

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

  def handle_event("update-filters", params, %{assigns: %{paginate_opts: paginate_opts}} = socket) do
    socket =
      socket
      |> assign(:paginate_opts, %{paginate_opts | page_number: @default_page})
      |> assign(:current_filters, params)
      |> assign(:currently_filtering, params != @default_filters)
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

  def handle_info(
        %Broadcast{event: "presence_diff", payload: %{leaves: leaves}},
        %{assigns: %{org: org, product: product}} = socket
      ) do
    devices = Devices.get_devices_by_org_id_and_product_id(org.id, product.id)
    joins = Presence.list("product:#{product.id}:devices")

    socket =
      assign_display_devices(socket, sync_devices(devices, %{joins: joins, leaves: leaves}))

    {:noreply, socket}
  end

  defp assign_statuses(org_id, product_id) do
    Devices.get_devices_by_org_id_and_product_id(org_id, product_id)
    |> sync_devices(%{joins: Presence.list("product:#{product_id}:devices"), leaves: %{}})
  end

  defp do_sort(%{assigns: %{devices: devices, current_sort: current_sort}} = socket) do
    current_sort = String.to_existing_atom(current_sort)
    sorter = sorter(current_sort, socket.assigns.sort_direction)
    devices = Enum.sort_by(devices, &Map.get(&1, current_sort), sorter)
    assign(socket, :devices, devices)
  end

  defp sorter(:last_communication, :desc), do: &(date_order(&1, &2) != :lt)
  defp sorter(:last_communication, :asc), do: &(date_order(&1, &2) != :gt)
  defp sorter(_, :desc), do: &>=/2
  defp sorter(_, :asc), do: &<=/2

  defp date_order(nil, nil), do: :eq
  defp date_order(_, nil), do: :gt
  defp date_order(nil, _), do: :lt
  defp date_order(a, b), do: DateTime.compare(a, b)

  defp do_paginate(%{assigns: %{devices: devices, paginate_opts: paginate_opts}} = socket) do
    start_index = (paginate_opts.page_number - 1) * paginate_opts.page_size
    devices = Enum.slice(devices, start_index, paginate_opts.page_size)

    socket
    |> assign_page_count()
    |> assign(:devices, devices)
  end

  defp do_filter(socket, %{"connection" => connection} = filters) do
    connection_status_match =
      &Enum.filter(&1, fn device ->
        if connection == "1" do
          device.status != "offline"
        else
          device.status == "offline"
        end
      end)

    apply_filter(socket, filters, "connection", connection_status_match)
  end

  defp do_filter(socket, %{"firmware_version" => version} = filters) do
    version_match =
      &Enum.filter(&1, fn device ->
        !is_nil(device.firmware_metadata) && device.firmware_metadata.version == version
      end)

    apply_filter(socket, filters, "firmware_version", version_match)
  end

  defp do_filter(socket, %{"healthy" => healthy} = filters) do
    healthy_match = &Enum.filter(&1, fn device -> device.healthy == (healthy == "1") end)

    apply_filter(socket, filters, "healthy", healthy_match)
  end

  defp do_filter(socket, %{"id" => id} = filters) do
    id_match = &Enum.filter(&1, fn device -> device.identifier =~ id end)

    apply_filter(socket, filters, "id", id_match)
  end

  defp do_filter(socket, %{"tag" => tag} = filters) do
    tag_match = &Enum.filter(&1, fn device -> Enum.any?(device.tags, fn t -> t =~ tag end) end)

    apply_filter(socket, filters, "tag", tag_match)
  end

  defp do_filter(socket, _) do
    socket
  end

  defp apply_filter(
         %{assigns: %{devices: devices}} = socket,
         filters,
         filter_key,
         filter_function
       ) do
    filters = Map.delete(filters, filter_key)

    devices = filter_function.(devices)

    socket
    |> assign(:devices, devices)
    |> do_filter(filters)
  end

  defp parse_filters(filter) do
    keys = @default_filters |> Map.keys()
    filters = Map.take(filter, keys)
    :maps.filter(fn _, v -> v != "" end, filters)
  end

  defp sync_devices(devices, %{joins: joins, leaves: leaves}) do
    for device <- devices do
      id = to_string(device.id)

      cond do
        meta = joins[id] ->
          fields = [
            :firmware_metadata,
            :last_communication,
            :status,
            :fwup_progress,
            :console_available
          ]

          updates = Map.take(meta, fields)
          Map.merge(device, updates)

        leaves[id] ->
          # We're counting a device leaving as its last_communication. This is
          # slightly inaccurate to set here, but only by a minuscule amount
          # and saves DB calls and broadcasts
          disconnect_time = DateTime.truncate(DateTime.utc_now(), :second)

          device
          |> Map.put(:last_communication, disconnect_time)
          |> Map.put(:status, "offline")
          |> Map.put(:fwup_progress, nil)

        true ->
          device
      end
    end
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

  defp assign_page_count(%{assigns: %{devices: devices, paginate_opts: paginate_opts}} = socket) do
    page_count = Float.ceil(length(devices) / paginate_opts.page_size) |> trunc

    assign(socket, :paginate_opts, %{paginate_opts | total_pages: page_count})
  end

  defp assign_display_devices(%{assigns: %{org: org, product: product}} = socket) do
    devices = assign_statuses(org.id, product.id)
    assign_display_devices(socket, devices)
  end

  defp assign_display_devices(%{assigns: %{current_filters: filters}} = socket, devices) do
    socket
    |> assign(:devices, devices)
    |> do_filter(parse_filters(filters))
    |> do_sort()
    |> do_paginate()
  end

  defp firmware_versions(product_id) do
    Firmwares.get_firmwares_by_product(product_id) |> Enum.map(& &1.version)
  end
end
