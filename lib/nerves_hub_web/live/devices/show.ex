defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.AuditLogs
  alias NervesHub.AuditLogs.Templates
  alias NervesHub.Deployments
  alias NervesHub.Devices
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Metrics
  alias NervesHub.Devices.UpdatePayload
  alias NervesHub.Extensions.Health
  alias NervesHub.Firmwares
  alias NervesHub.Repo
  alias NervesHub.Scripts
  alias NervesHub.Tracker

  alias NervesHubWeb.Components.AuditLogFeed
  alias NervesHubWeb.Components.DeviceHeader
  alias NervesHubWeb.Components.DeviceLocation
  alias NervesHubWeb.Components.FwupProgress
  alias NervesHubWeb.Components.Utils

  alias Phoenix.Socket.Broadcast

  @running_script_placeholder "Running Script.."

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: product} = socket.assigns

    device = Devices.get_device_by_identifier!(org, device_identifier, :latest_connection)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}:internal")
      socket.endpoint.subscribe("device:#{device.identifier}:extensions")
      socket.endpoint.subscribe("firmware")
    end

    socket
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> sidebar_tab(:devices)
    |> assign(:device, device)
    |> assign(:device_connection, device_connection(device))
    |> assign(:console_active?, Tracker.console_active?(device))
    |> assign(:deployment, device.deployment)
    |> assign(:update_information, Devices.resolve_update(device))
    |> assign(:firmwares, Firmwares.get_firmware_for_device(device))
    |> assign(:alarms, Alarms.get_current_alarms_for_device(device))
    |> assign(:extension_overrides, extension_overrides(device, product))
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> assign(:scripts, scripts_with_output(product))
    |> assign_metadata()
    |> schedule_health_check_timer()
    |> assign(:fwup_progress, nil)
    |> audit_log_assigns(1)
    |> assign(:eligible_deployments, Deployments.eligible_deployments(device))
    |> ok()
  end

  def handle_info(%Broadcast{topic: "firmware", event: "created"}, socket) do
    firmware = Firmwares.get_firmware_for_device(socket.assigns.device)
    {:noreply, assign(socket, :firmwares, firmware)}
  end

  def handle_info(%Broadcast{event: "connection:heartbeat"}, socket) do
    %{device: device, org: org} = socket.assigns

    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier, :latest_connection)

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
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(device.id))
    |> assign_metadata()
    |> noreply
  end

  def handle_info(:check_health_interval, socket) do
    timer_ref = Process.send_after(self(), :check_health_interval, 65_000)

    Health.request_health_check(socket.assigns.device)

    socket
    |> assign(:health_check_timer, timer_ref)
    |> noreply()
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

  def handle_event(
        "set-deployment",
        %{"deployment_id" => deployment_id},
        %{assigns: %{user: user, device: device, eligible_deployments: eligible_deployments}} =
          socket
      ) do
    deployment = Enum.find(eligible_deployments, &(&1.id == String.to_integer(deployment_id)))
    device = Devices.update_deployment(device, deployment)
    _ = Templates.audit_device_deployment_update(user, device, deployment)

    socket
    |> assign(:device, device)
    |> assign(:deployment, deployment)
    |> put_flash(:info, "Deployment successfully updated")
    |> noreply()
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

  def handle_event(
        "run-script",
        %{"idx" => index},
        %{assigns: %{device: device, scripts: scripts, org_user: org_user}} = socket
      ) do
    authorized!(:"support_script:run", org_user)

    {script, idx} = Enum.at(scripts, String.to_integer(index))

    socket
    |> assign(:scripts, update_script_output(scripts, idx, @running_script_placeholder))
    |> start_async({:run_script, idx}, fn -> Scripts.Runner.send(device, script) end)
    |> noreply()
  end

  def handle_event(
        "clear-script-output",
        %{"idx" => index},
        %{assigns: %{scripts: scripts}} = socket
      ) do
    socket
    |> assign(:scripts, update_script_output(scripts, String.to_integer(index), nil))
    |> noreply()
  end

  def handle_event(
        "remove-from-deployment",
        _,
        %{assigns: %{device: device}} = socket
      ) do
    device =
      device
      |> Devices.clear_deployment()
      |> Repo.preload(:deployment)

    socket
    |> assign(:device, device)
    |> assign(:deployment, nil)
    |> assign(:eligible_deployments, Deployments.eligible_deployments(device))
    |> put_flash(:info, "Device successfully removed from the deployment")
    |> noreply()
  end

  def handle_async(
        {:run_script, index},
        result,
        %{assigns: %{scripts: scripts}} = socket
      ) do
    output =
      case result do
        {:ok, output} ->
          output

        e ->
          inspect(e)
      end

    socket
    |> assign(:scripts, update_script_output(scripts, index, output))
    |> noreply()
  end

  defp scripts_with_output(product) do
    product
    |> Scripts.all_by_product()
    |> Enum.map(&Map.put(&1, :output, nil))
    |> Enum.with_index()
  end

  defp update_script_output(scripts, index, output) do
    List.update_at(scripts, index, fn {script, idx} ->
      {%{script | output: output}, idx}
    end)
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

  defp schedule_health_check_timer(%{assigns: %{device: device}} = socket) do
    if connected?(socket) and device.extensions.health do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end

  defp audit_log_assigns(%{assigns: %{device: device}} = socket, page_number) do
    {logs, audit_pager} = AuditLogs.logs_for_feed(device, %{page: page_number, page_size: 5})

    audit_pager = Map.from_struct(audit_pager)

    socket
    |> assign(:audit_logs, logs)
    |> assign(:audit_pager, audit_pager)
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

  defp has_description?(description) do
    is_binary(description) and byte_size(description) > 0
  end

  defp format_key(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp extension_overrides(device, product) do
    device.extensions
    |> Map.from_struct()
    |> Enum.filter(fn {extension, enabled} ->
      enabled == false and product.extensions[extension]
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp running_script_placeholder(), do: @running_script_placeholder

  defp script_button_text(output) when output == @running_script_placeholder or is_nil(output),
    do: "Run"

  defp script_button_text(_), do: "Close"

  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end
end
