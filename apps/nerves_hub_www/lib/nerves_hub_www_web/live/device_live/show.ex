defmodule NervesHubWWWWeb.DeviceLive.Show do
  use Phoenix.LiveView

  alias NervesHubDevice.Presence

  alias NervesHubWebCore.{Repo, Accounts.AuditLog}

  alias Phoenix.Socket.Broadcast

  defdelegate device_status(device), to: Presence

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("show.html", assigns)
  end

  def mount(session, socket) do
    socket =
      socket
      |> assign(:device, session.device)
      |> assign(:device_status, device_status(session.device))
      |> assign(:user, session.user)

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

  defp do_reboot(socket, :allowed) do
    {:ok, _audit_log} =
      AuditLog.build(socket.assigns.user, socket.assigns.device, :update, %{reboot: true})
      |> Repo.insert()

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "reboot", %{})

    socket =
      socket
      |> put_flash(:info, "Device Reboot Requested")
      |> assign(:device_status, "reboot-requested")

    {:noreply, socket}
  end

  defp do_reboot(socket, :blocked) do
    msg = "User not authorized to reboot this device"

    {:ok, _audit_log} =
      AuditLog.build(
        socket.assigns.user,
        socket.assigns.device,
        :update,
        %{reboot: false, message: msg}
      )
      |> Repo.insert()

    socket =
      socket
      |> put_flash(:error, msg)
      |> assign(:device_status, "reboot-blocked")

    {:noreply, socket}
  end
end
