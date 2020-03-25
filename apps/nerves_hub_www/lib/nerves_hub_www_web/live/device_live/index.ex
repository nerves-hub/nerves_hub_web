defmodule NervesHubWWWWeb.DeviceLive.Index do
  use NervesHubWWWWeb, :live_view

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.{Accounts, Products, Devices}
  alias NervesHubWWWWeb.DeviceView

  alias Phoenix.Socket.Broadcast

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
      |> assign(:devices, assign_statuses(org_id, product_id))
      |> assign(:current_sort, "identifier")
      |> assign(:sort_direction, :asc)

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
  def handle_event("sort", value, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{sort_direction: sort_direction} = socket.assigns

    # switch sort direction for column because
    sort_direction = if sort_direction == :desc, do: :asc, else: :desc

    socket =
      socket
      |> assign(sort_direction: sort_direction)
      |> do_sort()

    {:noreply, socket}
  end

  # User has clicked a new column to sort
  def handle_event("sort", value, socket) do
    socket =
      socket
      |> assign(:current_sort, value)
      |> assign(:sort_direction, :asc)
      |> do_sort()

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{event: "presence_diff", payload: payload},
        %{assigns: %{devices: devices}} = socket
      ) do
    socket =
      socket
      |> assign(:devices, sync_devices(devices, payload))
      |> case do
        %{assigns: %{current_sort: "status"}} = socket -> do_sort(socket)
        socket -> socket
      end

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

  defp sync_devices(devices, %{joins: joins, leaves: leaves}) do
    for device <- devices do
      id = to_string(device.id)

      cond do
        meta = joins[id] ->
          fields = [:firmware_metadata, :last_communication, :status, :fwup_progress]
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
end
