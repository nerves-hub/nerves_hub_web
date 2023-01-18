defmodule NervesHubWWWWeb.DeviceLive.Show do
  use NervesHubWWWWeb, :live_view

  alias NervesHubDevice.Presence

  alias NervesHubWebCore.{Accounts, AuditLogs, Devices, Devices.Device, Repo, Products}

  alias Phoenix.Socket.Broadcast

  def render(assigns) do
    NervesHubWWWWeb.DeviceView.render("show.html", assigns)
  end

  def mount(
        _params,
        %{
          "auth_user_id" => user_id,
          "org_id" => org_id,
          "product_id" => product_id,
          "device_id" => device_id
        },
        socket
      ) do
    socket =
      socket
      |> assign_new(:user, fn -> Accounts.get_user!(user_id) end)
      |> assign_new(:org, fn -> Accounts.get_org!(org_id) end)
      |> assign_new(:product, fn -> Products.get_product!(product_id) end)
      |> assign_new(:device, fn ->
        Devices.get_device_by_product(device_id, product_id, org_id)
      end)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{socket.assigns.device.id}")
      socket.endpoint.subscribe("product:#{product_id}:devices")
    end

    socket =
      socket
      |> assign(:device, sync_device(socket.assigns.device))
      |> assign(:page_title, socket.assigns.device.identifier)
      |> audit_log_assigns(1)

    {:ok, socket}
  rescue
    e ->
      socket_error(socket, live_view_error(e))
  end

  # Catch-all to handle when LV sessions change.
  # Typically this is after a deploy when the
  # session structure in the module has changed
  # for mount/3
  def mount(_, _, socket) do
    socket_error(socket, live_view_error(:update))
  end

  def handle_info(
        %Broadcast{event: "presence_diff", payload: payload},
        %{assigns: %{device: device}} = socket
      ) do
    {:noreply, assign(socket, :device, sync_device(device, payload))}
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("reboot", _value, %{assigns: %{device: device, user: user}} = socket) do
    user = Repo.preload(user, :org_users)

    case Enum.find(user.org_users, &(&1.org_id == device.org_id)) do
      %{role: :admin} -> do_reboot(socket, :allowed)
      _ -> do_reboot(socket, :blocked)
    end
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> audit_log_assigns(String.to_integer(page_num))}
  end

  def handle_event(
        "toggle_health_state",
        _params,
        %{assigns: %{device: device, user: user}} = socket
      ) do
    params = %{healthy: !device.healthy}

    socket =
      case Devices.update_device(device, params) do
        {:ok, updated_device} ->
          AuditLogs.audit!(user, device, :update, params)
          assign(socket, :device, updated_device)

        {:error, _changeset} ->
          put_flash(socket, :error, "Failed to mark health state")
      end

    {:noreply, socket}
  end

  def handle_event(
        "delete-certificate",
        %{"serial" => serial},
        %{assigns: %{device: device}} = socket
      ) do
    certs = device.device_certificates

    with db_cert <- Enum.find(certs, &(&1.serial == serial)),
         {:ok, _db_cert} <- Devices.delete_device_certificate(db_cert),
         updated_certs = Enum.reject(certs, &(&1.serial == serial)) do
      {:noreply, assign(socket, device: %{device | device_certificates: updated_certs})}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete certificate #{serial}")}
    end
  end

  def handle_event("restore", _, socket) do
    case Devices.restore_device(socket.assigns.device) do
      {:ok, device} ->
        {:noreply, assign(socket, device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to restore device")}
    end
  end

  def handle_event("destroy", _, socket) do
    case Repo.destroy(socket.assigns.device) do
      {:ok, _device} ->
        path =
          Routes.device_path(socket, :index, socket.assigns.org.name, socket.assigns.product.name)

        {:noreply, redirect(socket, to: path)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to destroy device")}
    end
  end

  def handle_event("delete", _, socket) do
    case Devices.delete_device(socket.assigns.device) do
      {:ok, %{device: device}} ->
        {:noreply, assign(socket, device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to delete device")}
    end
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket, page_number) do
    logs = AuditLogs.logs_for_feed(device, %{page: page_number, page_size: 5})

    socket
    |> assign(:audit_logs, logs)
    |> assign(:resource_id, device.id)
  end

  defp do_reboot(socket, :allowed) do
    AuditLogs.audit!(socket.assigns.user, socket.assigns.device, :update, %{reboot: true})

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "reboot", %{})

    socket =
      socket
      |> put_flash(:info, "Device Reboot Requested")
      |> assign(:device, %{socket.assigns.device | status: "reboot-requested"})

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
      |> assign(:device, %{socket.assigns.device | status: "reboot-blocked"})

    {:noreply, socket}
  end

  defp sync_device(device, payload \\ nil)
  defp sync_device(%{device: device}, payload), do: sync_device(device, payload)
  defp sync_device(%{assigns: %{device: device}}, payload), do: sync_device(device, payload)

  defp sync_device(%Device{id: id} = device, nil) do
    joins = Map.put(%{}, to_string(id), Presence.find(device))
    sync_device(device, %{joins: joins})
  end

  defp sync_device(%Device{id: id} = device, payload) when is_map(payload) do
    id = to_string(id)
    joins = Map.get(payload, :joins, %{})
    leaves = Map.get(payload, :leaves, %{})

    device = Repo.preload(device, :device_certificates, force: true)

    cond do
      meta = joins[id] ->
        updates =
          Map.take(meta, [
            :console_available,
            :firmware_metadata,
            :fwup_progress,
            :last_communication,
            :status
          ])

        Map.merge(device, updates)

      leaves[id] ->
        # We're counting a device leaving as its last_communication. This is
        # slightly inaccurate to set here, but only by a minuscule amount
        # and saves DB calls and broadcasts
        disconnect_time = DateTime.truncate(DateTime.utc_now(), :second)

        device
        |> Map.put(:console_available, false)
        |> Map.put(:fwup_progress, nil)
        |> Map.put(:last_communication, disconnect_time)
        |> Map.put(:status, "offline")

      true ->
        device
    end
  end
end
