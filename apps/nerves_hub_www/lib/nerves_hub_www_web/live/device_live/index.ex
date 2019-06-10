defmodule NervesHubWWWWeb.DeviceLive.Index do
  use Phoenix.LiveView

  alias NervesHubDevice.Presence
  alias NervesHubWebCore.Devices
  alias NervesHubWebCore.Accounts.Org

  alias Phoenix.Socket.Broadcast

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("index.html", assigns)
  end

  def mount(%{org_id: org_id, csrf_token: csrf_token}, socket) do
    if connected?(socket) do
      socket.endpoint.subscribe("devices:#{org_id}")
    end

    socket =
      socket
      |> assign(:devices, assign_statuses(org_id))
      |> assign(:current_sort, "identifier")
      |> assign(:csrf_token, csrf_token)
      |> assign(:sort_direction, :asc)

    {:ok, socket}
  end

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

  defp assign_statuses(org_id) do
    %Org{id: org_id}
    |> Devices.get_devices()
    |> sync_devices(%{joins: Presence.list("devices:#{org_id}"), leaves: %{}})
  end

  defp do_sort(%{assigns: %{devices: devices, current_sort: current_sort}} = socket) do
    current_sort = String.to_existing_atom(current_sort)
    devices = Enum.sort_by(devices, &Map.get(&1, current_sort), sorter(socket))
    assign(socket, :devices, devices)
  end

  defp sorter(%{assigns: %{sort_direction: :desc}}), do: &>=/2
  defp sorter(_), do: &<=/2

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
