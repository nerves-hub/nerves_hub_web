defmodule NervesHubWWWWeb.DeviceLive.Index do
  use Phoenix.LiveView

  alias NervesHubDevice.Presence

  alias NervesHubWebCore.{Repo, Accounts.AuditLog}

  alias Phoenix.Socket.Broadcast

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("index.html", assigns)
  end

  def mount(session, socket) do
    socket =
      socket
      |> assign(:devices, assign_statuses(session))
      |> assign(:current_sort, "identifier")
      |> assign(:sort_direction, :asc)

    if connected?(socket) do
      socket.endpoint.subscribe("devices:#{session.org_id}")
    end

    {:ok, socket}
  end

  # Handles event of user clicking the same field that is already sorted
  # For this case, we switch the sorting direction of same field
  def handle_event("sort", value, %{assigns: %{current_sort: current_sort}} = socket)
      when value == current_sort do
    %{devices: devices, sort_direction: sort_direction} = socket.assigns

    # switch sort direction for column because
    sort_direction = if sort_direction == :desc, do: :asc, else: :desc

    socket =
      socket
      |> assign(sort_direction: sort_direction)
      |> do_sort()

    {:noreply, socket}
  end

  # User has clicked a new column to sort
  def handle_event("sort", value, %{assigns: %{devices: devices}} = socket) do
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
      |> assign(:devices, update_statuses(devices, payload))
      |> case do
        %{assigns: %{current_sort: "status"}} = socket -> do_sort(socket)
        socket -> socket
      end

    {:noreply, socket}
  end

  defp assign_statuses(%{devices: devices, org_id: org_id}) do
    presences = Presence.list("devices:#{org_id}")

    for device <- devices do
      status = get_in(presences, [to_string(device.id), :status]) || "offline"
      %{device | status: status}
    end
  end

  defp do_sort(%{assigns: %{devices: devices, current_sort: current_sort}} = socket) do
    current_sort = String.to_existing_atom(current_sort)
    devices = Enum.sort_by(devices, &Map.get(&1, current_sort), sorter(socket))
    assign(socket, :devices, devices)
  end

  defp sorter(%{assigns: %{sort_direction: :desc}}), do: &>=/2
  defp sorter(_), do: &<=/2

  defp update_statuses(devices, %{joins: joins, leaves: leaves}) do
    for device <- devices do
      id = to_string(device.id)

      cond do
        meta = joins[id] -> %{device | status: meta.status}
        leaves[id] -> %{device | status: "offline"}
        true -> device
      end
    end
  end
end
