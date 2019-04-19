defmodule NervesHubWWWWeb.DeviceLive.Show do
  use Phoenix.LiveView

  alias NervesHubDevice.Presence

  alias NervesHubWebCore.{Repo, AuditLogs}

  alias Phoenix.Socket.Broadcast

  defdelegate device_status(device), to: Presence

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("show.html", assigns)
  end

  def mount(session, socket) do
    device_presence = Presence.find(session.device, %{status: "offline"})

    socket =
      socket
      |> assign(:console_available, device_presence[:console_available])
      |> assign(:device, session.device)
      |> assign(:device_status, device_presence.status)
      |> assign(:user, session.user)
      |> audit_log_assigns()

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{session.device.id}")
      socket.endpoint.subscribe("devices:#{session.device.org_id}")
    end

    {:ok, socket}
  end

  def handle_info(
        %Broadcast{event: "presence_diff", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    id_keys =
      [Map.keys(payload.joins), Map.keys(payload.leaves)]
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)

    socket =
      if device.id in id_keys do
        socket
        |> assign(:device_status, device_status(device))
        |> assign(:device, Repo.reload(device))
      else
        socket
      end

    {:noreply, socket}
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("reboot", _value, %{assigns: %{device: device, user: user}} = socket) do
    case Enum.find(user.org_users, &(&1.org_id == device.org_id)) do
      %{role: :admin} -> do_reboot(socket, :allowed)
      _ -> do_reboot(socket, :blocked)
    end
  end

  def handle_event(
        "paginate",
        page_num,
        %{assigns: %{audit_log_ids: ids, paginate_opts: paginate_opts}} = socket
      ) do
    # This LiveView stores an array of all its audit log's ids. On paginate
    # call, it gets the the index offset based on the page it is currently on
    # then slices out the number of ids equal to the set page_size starting
    # at that index. Then we query AuditLogs for only those specific records
    page_num = String.to_integer(page_num)
    start_index = (page_num - 1) * paginate_opts.page_size
    audit_logs = Enum.slice(ids, start_index, paginate_opts.page_size) |> AuditLogs.from_ids()

    socket =
      socket
      |> assign(:audit_logs, audit_logs)
      |> assign(:paginate_opts, %{paginate_opts | page_number: page_num})

    {:noreply, socket}
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket) do
    all_logs = AuditLogs.logs_for_feed(device)
    paginate_opts = %{page_number: 1, page_size: 10}

    socket
    |> assign(:audit_logs, Enum.slice(all_logs, 0, paginate_opts.page_size))
    |> assign(:audit_log_ids, Enum.map(all_logs, & &1.id))
    |> assign(:paginate_opts, paginate_opts)
    |> assign(:resource_id, device.id)
  end

  defp do_reboot(socket, :allowed) do
    AuditLogs.audit!(socket.assigns.user, socket.assigns.device, :update, %{reboot: true})

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "reboot", %{})

    socket =
      socket
      |> put_flash(:info, "Device Reboot Requested")
      |> assign(:device_status, "reboot-requested")

    {:noreply, socket}
  end

  defp do_reboot(socket, :blocked) do
    msg = "User not authorized to reboot this device"

    AuditLogs.audit!(socket.assigns.user, socket.assigns.device, :update, %{
      reboot: false,
      message: msg
    })

    socket =
      socket
      |> put_flash(:error, msg)
      |> assign(:device_status, "reboot-blocked")

    {:noreply, socket}
  end
end
