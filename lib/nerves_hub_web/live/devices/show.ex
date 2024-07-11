defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.DeviceHeader
  alias NervesHubWeb.Components.FwupProgress
  alias NervesHubWeb.Components.DeviceLocation

  alias Phoenix.Socket.Broadcast

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: product} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
      socket.endpoint.subscribe("firmware")
    end

    socket
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> assign(:tab_hint, :devices)
    |> assign(:device, device)
    |> assign(:status, Tracker.status(device))
    |> assign(:deployment, device.deployment)
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> assign(:fwup_progress, nil)
    |> audit_log_assigns(1)
    |> ok()
  end

  def handle_info(%Broadcast{topic: "firmware", event: "created"}, socket) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)
    {:noreply, assign(socket, :firmwares, firmware)}
  end

  def handle_info(%Broadcast{event: "connection:status", payload: payload}, socket) do
    {:noreply, assign(socket, :status, payload.status)}
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    %{device: device, org: org} = socket.assigns

    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier)

    socket
    |> assign(:device, device)
    |> assign(:status, payload.status)
    |> assign(:fwup_progress, nil)
    |> then(fn socket ->
      if(payload.status == "online", do: clear_flash(socket), else: socket)
    end)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: payload}, socket) do
    if payload.percent == 100 do
      socket
      |> put_flash(:info, "Update complete: The device will reboot shortly.")
      |> assign(:fwup_progress, nil)
      |> noreply()
    else
      {:noreply, assign(socket, :fwup_progress, payload.percent)}
    end
  end

  def handle_info(%Broadcast{event: "location:updated"}, socket) do
    %{device: device, org: org} = socket.assigns

    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier)

    {:noreply, assign(socket, :device, device)}
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("reboot", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:reboot", org_user)

    AuditLogs.audit!(user, device, "#{user.name} rebooted device #{device.identifier}")

    socket.endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

    {:noreply, put_flash(socket, :info, "Device reboot requested")}
  end

  def handle_event("reconnect", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:reconnect", org_user)

    AuditLogs.audit!(
      user,
      device,
      "#{user.name} requested the device (#{device.identifier}) reconnect"
    )

    socket.endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    {:noreply, put_flash(socket, :info, "Device reconnection requested")}
  end

  def handle_event("identify", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:identify", org_user)

    AuditLogs.audit!(
      user,
      device,
      "#{user.name} requested the device (#{device.identifier}) identify itself"
    )

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "identify", %{})

    {:noreply, put_flash(socket, :info, "Device identification requested")}
  end

  def handle_event("paginate", %{"page" => page_num}, socket) do
    {:noreply, socket |> audit_log_assigns(String.to_integer(page_num))}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:clear-penalty-box", org_user)

    {:ok, updated_device} = Devices.clear_penalty_box(device, user)

    {:noreply, assign(socket, :device, updated_device)}
  end

  def handle_event("toggle_health_state", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:toggle-updates", org_user)

    {:ok, updated_device} = Devices.toggle_health(device, user)

    {:noreply, assign(socket, :device, updated_device)}
  end

  def handle_event("restore", _, socket) do
    authorized!(:"device:restore", socket.assigns.org_user)

    {:ok, device} = Devices.restore_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_event("destroy", _, socket) do
    %{org: org, org_user: org_user, product: product, device: device} = socket.assigns

    authorized!(:"device:destroy", org_user)

    {:ok, _device} = Devices.destroy_device(device)

    socket
    |> put_flash(:info, "Device destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{org.name}/#{product.name}/devices")
    |> noreply()
  end

  def handle_event("delete", _, socket) do
    authorized!(:"device:delete", socket.assigns.org_user)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_event("clear-flash-" <> key_str, _, socket) do
    {:noreply, clear_flash(socket, String.to_existing_atom(key_str))}
  end

  def handle_event("push-update", %{"uuid" => uuid}, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{product: product, device: device, user: user} = socket.assigns

    {:ok, firmware} = Firmwares.get_firmware_by_product_and_uuid(product, uuid)
    {:ok, url} = Firmwares.get_firmware_url(firmware)
    {:ok, meta} = Firmwares.metadata_from_firmware(firmware)
    {:ok, device} = Devices.disable_updates(device, user)

    description =
      "#{user.name} pushed firmware #{firmware.version} #{firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)

    payload = %UpdatePayload{
      update_available: true,
      firmware_url: url,
      firmware_meta: meta
    }

    _ = NervesHubWeb.Endpoint.broadcast("device:#{device.id}", "deployments/update", payload)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Pushing firmware update")
    |> noreply()
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket, page_number) do
    logs = AuditLogs.logs_for_feed(device, %{page: page_number, page_size: 5})

    assign(socket, :audit_logs, logs)
  end

  defp connecting_code(device) do
    if device.deployment && device.deployment.connecting_code do
      """
      #{device.deployment.connecting_code}
      #{device.connecting_code}
      """
    else
      device.connecting_code
    end
  end
end
