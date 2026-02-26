defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Extensions.Health
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.DevicePage.ActivityTab
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias NervesHubWeb.Components.DevicePage.DetailsTab
  alias NervesHubWeb.Components.DevicePage.HealthTab
  alias NervesHubWeb.Components.DevicePage.LocalShellTab
  alias NervesHubWeb.Components.DevicePage.LogsTab
  alias NervesHubWeb.Components.DevicePage.SettingsTab
  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.FwupProgress
  alias NervesHubWeb.Presence
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.Socket.Broadcast

  require Logger

  @tab_components [ActivityTab, ConsoleTab, DetailsTab, HealthTab, LocalShellTab, LogsTab, SettingsTab]

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: product, user: user} = socket.assigns

    device = load_device(org, device_identifier)

    if connected?(socket) do
      Logger.metadata(device_id: device.id, user_id: user.id, product_id: product.id)
      socket.endpoint.subscribe("device:#{device.id}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}")
      socket.endpoint.subscribe("device:#{device.id}:extensions")
      socket.endpoint.subscribe("product:#{product.id}")
    end

    socket
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> sidebar_tab(:devices)
    |> selected_tab()
    |> general_assigns(device)
    |> schedule_health_check_timer()
    |> assign(:fwup_progress, nil)
    |> assign(:pinned?, Devices.device_pinned?(user.id, device.id))
    |> setup_presence_tracking()
    |> setup_tab_components(@tab_components)
    |> ok()
  end

  def handle_params(_params, _uri, socket) do
    socket
    |> update_tab_component_hooks()
    |> noreply()
  end

  def handle_info(:reload_device, socket) do
    %{org: org, device: device} = socket.assigns

    device = load_device(org, device.identifier)

    socket
    |> assign(:device, device)
    |> noreply()
  end

  def handle_info({Presence, {:join, presence}}, socket) do
    {:noreply, stream_insert(socket, :presences, presence)}
  end

  def handle_info({Presence, {:leave, presence}}, socket) do
    if presence.metas == [] do
      {:noreply, stream_delete(socket, :presences, presence)}
    else
      {:noreply, stream_insert(socket, :presences, presence)}
    end
  end

  def handle_info(%Broadcast{event: "connection:heartbeat"}, socket) do
    %{device: device} = socket.assigns

    {:noreply, assign(socket, :device_connection, Connections.get_latest_for_device(device.id))}
  end

  def handle_info(
        %Broadcast{event: "connection:status", payload: %{status: "online"}},
        %{assigns: %{device: device, org: org}} = socket
      ) do
    device = load_device(org, device.identifier)

    socket
    |> general_assigns(device)
    |> assign(:update_information, Devices.resolve_update(device))
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "connection:status", payload: %{status: "offline"}},
        %{assigns: %{device: device}} = socket
      ) do
    {:noreply, assign(socket, :device_connection, Connections.get_latest_for_device(device.id))}
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    %{device: previous_device, org: org} = socket.assigns

    device = load_device(org, previous_device.identifier)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
    |> async_console_status_check()
    |> assign(:fwup_progress, nil)
    |> assign(:update_information, Devices.resolve_update(device))
    |> then(fn socket ->
      if(payload.status == "online", do: clear_flash(socket), else: socket)
    end)
    |> maybe_send_metadata_updated_message(previous_device)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "console_joined"}, socket) do
    status = socket.assigns.console_online

    socket
    |> assign(:console_online, AsyncResult.ok(status, true))
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

  def handle_info(:check_health_interval, socket) do
    timer_ref = Process.send_after(self(), :check_health_interval, health_polling_seconds())

    Health.request_health_check(socket.assigns.device)

    socket
    |> assign(:health_check_timer, timer_ref)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "location:updated"}, socket) do
    %{device: device, org: org} = socket.assigns

    device = load_device(org, device.identifier)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_info(%Broadcast{event: "firmware:validated"}, socket) do
    %{device: device, org: org} = socket.assigns

    device = load_device(org, device.identifier)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Firmware validation received from the device")
    |> noreply()
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("pin", _value, %{assigns: %{user: user, device: device}} = socket) do
    case Devices.pin_device(user.id, device.id) do
      {:ok, _} ->
        socket
        |> assign(:pinned?, true)
        |> noreply()

      {:error, changeset} ->
        Logger.error("Could not pin device: #{inspect(changeset)}")

        socket
        |> put_flash(:info, "Could not pin device. Please contact support.")
        |> noreply()
    end
  end

  def handle_event("unpin", _value, %{assigns: %{user: user, device: device}} = socket) do
    case Devices.unpin_device(user.id, device.id) do
      {:ok, _} ->
        socket
        |> assign(:pinned?, false)
        |> noreply()

      {:error, changeset} ->
        Logger.error("Could not unpin device: #{inspect(changeset)}")

        socket
        |> put_flash(:info, "Could not unpin device. Please contact support.")
        |> noreply()
    end
  end

  def handle_event("reboot", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:reboot", org_user)

    DeviceEvents.reboot(device, user)

    {:noreply, put_flash(socket, :info, "Device reboot requested")}
  end

  def handle_event("reconnect", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:reconnect", org_user)

    DeviceTemplates.audit_request_action(user, device, "reconnect")

    socket.endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    {:noreply, put_flash(socket, :info, "Device reconnection requested")}
  end

  def handle_event("identify", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:identify", org_user)

    DeviceEvents.identify(device, user)

    {:noreply, put_flash(socket, :info, "Device identification requested")}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:clear-penalty-box", org_user)

    {:ok, updated_device} = Devices.clear_penalty_box(device, user)

    socket
    |> assign(:device, updated_device)
    |> put_flash(:info, "Device removed from the penalty box, and firmware updates enabled.")
    |> noreply()
  end

  def handle_event("toggle-deployment-firmware-updates", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:toggle-updates", org_user)

    {:ok, updated_device} = Devices.toggle_automatic_updates(device, user)

    message = [
      "Firmware updates ",
      (updated_device.updates_enabled && "enabled") || "disabled",
      "."
    ]

    socket
    |> assign(:device, updated_device)
    |> put_flash(:info, Enum.join(message))
    |> noreply()
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
    |> push_navigate(to: ~p"/org/#{org}/#{product}/devices")
    |> noreply()
  end

  def handle_event("delete", _, socket) do
    authorized!(:"device:delete", socket.assigns.org_user)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_event("set-deployment-group", %{"deployment_id" => ""}, socket) do
    socket
    |> put_flash(:error, "Please select a deployment group.")
    |> noreply()
  end

  defp load_device(org, identifier) do
    Devices.get_device_by_identifier!(org, identifier, [
      :product,
      :firmware,
      :latest_connection,
      :latest_health
    ])
  end

  defp setup_presence_tracking(%{assigns: %{device: device, user: user}} = socket) do
    topic = "device-#{device.identifier}"
    socket = stream(socket, :presences, [])

    with true <- connected?(socket),
         {:ok, _} <- Presence.track_user(topic, user.id, %{name: user.name}),
         :ok <- Presence.subscribe(topic) do
      stream(socket, :presences, Presence.list_present_users(topic))
    else
      _ ->
        socket
    end
  end

  defp schedule_health_check_timer(socket) do
    %{device: device, product: product} = socket.assigns

    if connected?(socket) and health_extension_enabled?(product, device) do
      timer_ref = Process.send_after(self(), :check_health_interval, 500)
      assign(socket, :health_check_timer, timer_ref)
    else
      assign(socket, :health_check_timer, nil)
    end
  end

  defp health_extension_enabled?(product, device) do
    product.extensions.health and device.extensions.health
  end

  defp show_firmware_status_box(device) do
    device.firmware_validation_status in [:validated, :not_validated] or device.firmware_auto_revert_detected
  end

  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end

  defp general_assigns(socket, device) do
    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
    |> async_console_status_check()
  end

  defp maybe_send_metadata_updated_message(socket, previous_device) do
    %{device: device} = socket.assigns

    if not is_nil(device.firmware_metadata) and not is_nil(previous_device.firmware_metadata) and
         (device.firmware_metadata.architecture != previous_device.firmware_metadata.architecture or
            device.firmware_metadata.platform != previous_device.firmware_metadata.platform) do
      send(self(), :platform_or_architecture_updated)
    end

    socket
  end

  def async_console_status_check(socket) do
    device_id = socket.assigns.device.id

    assign_async(socket, :console_online, fn ->
      {:ok, %{console_online: Tracker.console_active?(device_id)}}
    end)
  end

  def show_menu(id, js \\ %JS{}) do
    JS.show(js, transition: "fade-in", to: "##{id}")
  end

  def hide_menu(id, js \\ %JS{}) do
    JS.hide(js, transition: "fade-out", to: "##{id}")
  end

  def selected_tab(socket) do
    assign(socket, :tab, socket.assigns.live_action || :details)
  end

  defp tab(assigns) do
    ~H"""
    <.link
      data-selected={"#{@selected}"}
      class="px-6 py-2 h-11 font-normal text-sm text-zinc-300 hover:border-b hover:border-indigo-500 data-[selected=true]:text-neutral-50 data-[selected=true]:border-b data-[selected=true]:border-indigo-500 relative -bottom-px"
      phx-click={JS.set_attribute({"data-selected", "false"}, to: "#tabs a") |> JS.set_attribute({"data-selected", "true"})}
      patch={@path}
    >
      {@display}
    </.link>
    """
  end

  defp health_polling_seconds() do
    Application.get_env(:nerves_hub, :extension_config, [])
    |> get_in([:health, :ui_polling_seconds])
    |> :timer.seconds()
  end

  def render_tab(assigns) do
    ~H"""
    <ActivityTab.render :if={@tab == :activity} {assigns} />
    <ConsoleTab.render :if={@tab == :console} {assigns} />
    <DetailsTab.render :if={@tab == :details} {assigns} />
    <HealthTab.render :if={@tab == :health} {assigns} />
    <LocalShellTab.render :if={@tab == :local_shell} {assigns} />
    <LogsTab.render :if={@tab == :logs} {assigns} />
    <SettingsTab.render :if={@tab == :settings} {assigns} />
    """
  end
end
