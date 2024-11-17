defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Firmwares
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.DeviceHeader
  alias NervesHubWeb.Components.FwupProgress
  alias NervesHubWeb.Components.DeviceLocation
  alias NervesHubWeb.Components.Utils

  alias Phoenix.Socket.Broadcast

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: product} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier, :latest_connection)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}:internal")
      socket.endpoint.subscribe("firmware")
    end

    socket
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> assign(:tab_hint, :devices)
    |> assign(:device, device)
    |> assign(:device_connection, device_connection(device))
    |> assign(:console_active?, Tracker.console_active?(device))
    |> assign(:deployment, device.deployment)
    |> assign(:update_information, Devices.resolve_update(device))
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> assign(:latest_metrics, Devices.Metrics.get_latest_metric_set_for_device(device.id))
    |> assign(:latest_custom_metrics, Devices.Metrics.get_latest_custom_metrics(device.id))
    |> assign_metadata()
    |> schedule_health_check_timer()
    |> assign(:fwup_progress, nil)
    |> audit_log_assigns(1)
    |> ok()
  end

  def handle_info(%Broadcast{topic: "firmware", event: "created"}, socket) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)
    {:noreply, assign(socket, :firmwares, firmware)}
  end

  def handle_info(%Broadcast{event: "connection:heartbeat"}, socket) do
    %{device: device, org: org} = socket.assigns

    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device_connection(device))
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "connection:status"},
        %{assigns: %{device: device}} = socket
      ) do
    {:noreply, assign(socket, :device_connection, Connections.get_latest_for_device(device.id))}
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    %{device: device, org: org} = socket.assigns

    # Get device with its latest connection data preloaded
    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier, :latest_connection)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device_connection(device))
    |> assign(:console_active?, Tracker.console_active?(device))
    |> assign(:fwup_progress, nil)
    |> assign(:update_information, Devices.resolve_update(device))
    |> then(fn socket ->
      if(payload.status == "online", do: clear_flash(socket), else: socket)
    end)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "console_joined"}, socket) do
    socket
    |> assign(:console_active?, true)
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

  def handle_info(
        %Broadcast{event: "health_check_report"},
        %{assigns: %{device: device}} = socket
      ) do
    socket
    |> assign(:latest_metrics, Devices.Metrics.get_latest_metric_set_for_device(device.id))
    |> assign(:latest_custom_metrics, Devices.Metrics.get_latest_custom_metrics(device.id))
    |> assign_metadata()
    |> noreply
  end

  def handle_info(:check_health_interval, socket) do
    timer_ref = Process.send_after(self(), :check_health_interval, 65_000)

    socket.endpoint.broadcast("device:#{socket.assigns.device.id}", "check_health", %{})

    {:noreply, assign(socket, :health_check_timer, timer_ref)}
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

  def handle_event("toggle-health-check-auto-refresh", _value, socket) do
    if timer_ref = socket.assigns.health_check_timer do
      _ = Process.cancel_timer(timer_ref)
      {:noreply, assign(socket, :health_check_timer, nil)}
    else
      {:noreply, schedule_health_check_timer(socket)}
    end
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

    _ = NervesHubWeb.Endpoint.broadcast("device:#{device.id}", "devices/update-manual", payload)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Pushing firmware update")
    |> noreply()
  end

  def handle_event("push-available-update", _, socket) do
    authorized!(:"device:push-update", socket.assigns.org_user)

    %{device: device, deployment: deployment, user: user} = socket.assigns

    deployment = NervesHub.Repo.preload(deployment, :firmware)

    description =
      "#{user.name} pushed available firmware update #{deployment.firmware.version} #{deployment.firmware.uuid} to device #{device.identifier}"

    AuditLogs.audit!(user, device, description)

    case Devices.told_to_update(device, deployment) do
      {:ok, inflight_update} ->
        _ =
          NervesHubWeb.Endpoint.broadcast(
            "device:#{device.id}",
            "deployments/update",
            inflight_update
          )

        socket
        |> put_flash(:info, "Pushing available firmware update")
        |> noreply()

      :error ->
        Logger.error(
          "An inflight update could not be created or found for the device #{device.identifier} (#{device.id})"
        )

        socket
        |> put_flash(
          :info,
          "There was an error sending the update to the device. Please contact support."
        )
        |> noreply()
    end
  end

  defp device_connection(%{device_connections: [connection]}), do: connection
  defp device_connection(_), do: nil

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    health = Devices.get_latest_health(device.id)

    metadata =
      if health, do: health.data["metadata"] || %{}, else: %{}

    socket
    |> assign(:metadata, Map.drop(metadata, standard_keys(device)))
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do:
      firmware_metadata
      |> Map.keys()
      |> Enum.map(&to_string/1)

  defp schedule_health_check_timer(socket) do
    if connected?(socket) and device_health_check_enabled?() do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end

  defp device_health_check_enabled?() do
    Application.get_env(:nerves_hub, :device_health_check_enabled)
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
