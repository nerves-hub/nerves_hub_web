defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Consoles
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Pinning
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.Updates
  alias NervesHub.Extensions
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Products
  alias NervesHub.Tracker
  alias NervesHubWeb.Components.DevicePage.ActivityTab
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias NervesHubWeb.Components.DevicePage.DataHistoryTab
  alias NervesHubWeb.Components.DevicePage.DetailsTab
  alias NervesHubWeb.Components.DevicePage.ErrorsTab
  alias NervesHubWeb.Components.DevicePage.FirmwareHistoryTab
  alias NervesHubWeb.Components.DevicePage.HealthTab
  alias NervesHubWeb.Components.DevicePage.LocalShellTab
  alias NervesHubWeb.Components.DevicePage.LogsTab
  alias NervesHubWeb.Components.DevicePage.NetworksTab
  alias NervesHubWeb.Components.DevicePage.SettingsTab
  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.UpdateProgress
  alias NervesHubWeb.Presence
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS
  alias Phoenix.Socket.Broadcast

  require Logger

  @tab_components [
    ActivityTab,
    ConsoleTab,
    DataHistoryTab,
    DetailsTab,
    ErrorsTab,
    FirmwareHistoryTab,
    HealthTab,
    LocalShellTab,
    LogsTab,
    NetworksTab,
    SettingsTab
  ]

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{current_scope: %{org: org, product: product, user: user} = scope} = socket.assigns

    device = load_device(scope, device_identifier)

    if connected?(socket) do
      Logger.metadata(device_id: device.id, user_id: user.id, product_id: product.id)
      PubSub.subscribe(device.id)
      Consoles.PubSub.subscribe_console_watcher(device.id)
      Extensions.PubSub.subscribe_reports(device.id)
      Products.PubSub.subscribe(product.id)
    end

    socket
    |> assign(%{org: org, product: product, user: user})
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> sidebar_tab(:devices)
    |> selected_tab()
    |> general_assigns(device)
    |> watch_health()
    |> load_inprogress_firmware_update()
    |> assign(:pinned?, Pinning.device_pinned?(user.id, device.id))
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
    %{current_scope: scope, device: device} = socket.assigns

    device = load_device(scope, device.identifier)

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

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    %{device: previous_device, current_scope: scope} = socket.assigns

    device = load_device(scope, previous_device.identifier)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
    |> load_inprogress_firmware_update()
    |> async_console_status_check()
    |> assign(:update_information, Updates.resolve_update(device))
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

  def handle_info(%Broadcast{event: "firmware_update_progress", payload: %{"stage" => stage}}, socket)
      when stage == "expired" do
    socket
    |> put_flash(:notice, "Update aborted: No updates have been received in the last 15 minutes.")
    |> assign(:firmware_update_progress, nil)
    |> assign(:firmware_update_stage, nil)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "firmware_update_progress", payload: %{"stage" => stage}}, socket)
      when stage == "completed" do
    socket
    |> put_flash(:info, "Update complete: The device will reboot shortly.")
    |> assign(:firmware_update_progress, nil)
    |> assign(:firmware_update_stage, stage)
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "firmware_update_progress", payload: %{"stage" => stage, "progress" => percent}},
        socket
      )
      when stage in ["downloading", "updating"] do
    socket
    |> assign(:firmware_update_progress, percent)
    |> assign(:firmware_update_stage, stage)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "firmware_update_progress", payload: %{"stage" => stage}}, socket) do
    socket
    |> assign(:firmware_update_progress, nil)
    |> assign(:firmware_update_stage, stage)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "location:updated"}, socket) do
    %{device: device, current_scope: scope} = socket.assigns

    device = load_device(scope, device.identifier)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_info(%Broadcast{event: "network_identities:updated"}, socket) do
    %{device: device, current_scope: scope} = socket.assigns

    device = load_device(scope, device.identifier)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_info(%Broadcast{event: "firmware:validated"}, socket) do
    %{device: device, current_scope: scope} = socket.assigns

    device = load_device(scope, device.identifier)

    socket
    |> assign(:device, device)
    |> put_flash(:info, "Firmware validation received from the device")
    |> noreply()
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  def handle_event("pin", _value, %{assigns: %{user: user, device: device}} = socket) do
    case Pinning.pin_device(user.id, device.id) do
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
    case Pinning.unpin_device(user.id, device.id) do
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
    %{current_scope: current_scope, user: user, device: device} = socket.assigns

    authorized!(:"device:reboot", current_scope)

    DeviceEvents.reboot(device, user)

    {:noreply, put_flash(socket, :info, "Device reboot requested")}
  end

  def handle_event("reconnect", _value, socket) do
    %{current_scope: current_scope, user: user, device: device} = socket.assigns

    authorized!(:"device:reconnect", current_scope)

    DeviceTemplates.audit_request_action(user, device, "reconnect")

    socket.endpoint.broadcast("device_socket:#{device.id}", "disconnect", %{})

    {:noreply, put_flash(socket, :info, "Device reconnection requested")}
  end

  def handle_event("identify", _value, socket) do
    %{current_scope: current_scope, user: user, device: device} = socket.assigns

    authorized!(:"device:identify", current_scope)

    DeviceEvents.identify(device, user)

    {:noreply, put_flash(socket, :info, "Device identification requested")}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    %{current_scope: current_scope, user: user, device: device} = socket.assigns

    authorized!(:"device:clear-penalty-box", current_scope)

    {:ok, updated_device} = Updates.clear_penalty_box(device, user)

    socket
    |> assign(:device, updated_device)
    |> put_flash(:info, "Device removed from the penalty box, and firmware updates enabled.")
    |> noreply()
  end

  def handle_event("set-update-mode", %{"mode" => mode}, socket) do
    %{current_scope: current_scope, user: user, device: device} = socket.assigns

    authorized!(:"device:toggle-updates", current_scope)

    mode = String.to_existing_atom(mode)

    case Updates.set_update_mode(device, mode, user) do
      {:ok, updated_device} ->
        socket
        |> assign(:device, updated_device)
        |> put_flash(:info, "Firmware updates set to #{String.downcase(update_mode_label(mode))}.")
        |> noreply()

      _error ->
        socket
        |> put_flash(
          :error,
          "We couldn't change how this device receives updates. Please contact support if this happens again."
        )
        |> noreply()
    end
  end

  def handle_event("restore", _, socket) do
    authorized!(:"device:restore", socket.assigns.current_scope)

    {:ok, device} = Devices.restore_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_event("destroy", _, socket) do
    %{org: org, current_scope: current_scope, product: product, device: device} = socket.assigns

    authorized!(:"device:destroy", current_scope)

    {:ok, _device} = Devices.destroy_device(device)

    socket
    |> put_flash(:info, "Device destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{org}/#{product}/devices")
    |> noreply()
  end

  def handle_event("delete", _, socket) do
    authorized!(:"device:delete", socket.assigns.current_scope)

    {:ok, device} = Devices.delete_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  def handle_event("set-deployment-group", %{"deployment_id" => ""}, socket) do
    socket
    |> put_flash(:error, "Please select a deployment group.")
    |> noreply()
  end

  # Ignore handle_async results that have come from other tabs
  # This can happen when a support script is run from the details tab, only for the user
  # to navigate to a different tab before the result arrives.
  def handle_async(_name, _async_fun_result, socket), do: {:noreply, socket}

  defp load_device(scope, identifier) do
    Devices.get_by_identifier!(scope, identifier, [
      :product,
      :latest_connection,
      :latest_health,
      :network_identities,
      :component_topology
    ])
  end

  defp load_inprogress_firmware_update(socket) do
    socket.assigns.device
    |> FirmwareUpdates.inflight_update_for()
    |> case do
      nil ->
        socket
        |> assign(:firmware_update_progress, nil)
        |> assign(:firmware_update_stage, nil)

      inflight_update ->
        socket
        |> assign(:firmware_update_progress, inflight_update.progress)
        |> assign(:firmware_update_stage, inflight_update.status)
    end
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

  # Tells the device's extensions channel that somebody is looking, which is the
  # whole of the page's involvement in health reporting: the pace, and the
  # `health:check` itself, belong to `NervesHub.Extensions.Health`. Every open
  # page used to run its own timer and ask the device directly, so two people on
  # one device meant two extra streams of requests on top of the platform's.
  #
  # There is nothing to give up again: watching lasts as long as this process,
  # and the reporting slows back down once the last page has closed.
  defp watch_health(socket) do
    %{device: device, product: product} = socket.assigns

    if connected?(socket) and health_extension_enabled?(product, device) do
      :ok = Extensions.PubSub.watch_health(device.id)
    end

    socket
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

  def render_tab(assigns) do
    ~H"""
    <ActivityTab.render :if={@tab == :activity} {assigns} />
    <ConsoleTab.render :if={@tab == :console} {assigns} />
    <DataHistoryTab.render :if={@tab == :data_history} {assigns} />
    <DetailsTab.render :if={@tab == :details} {assigns} />
    <ErrorsTab.render :if={@tab == :errors} {assigns} />
    <FirmwareHistoryTab.render :if={@tab == :firmware_history} {assigns} />
    <HealthTab.render :if={@tab == :health} {assigns} />
    <LocalShellTab.render :if={@tab == :local_shell} {assigns} />
    <LogsTab.render :if={@tab == :logs} {assigns} />
    <NetworksTab.render :if={@tab == :networks} {assigns} />
    <SettingsTab.render :if={@tab == :settings} {assigns} />
    """
  end

  @doc false
  def update_modes() do
    [
      {:automatic, "Automatic", "This device's deployment group sends it firmware on its own schedule."},
      {:device_managed, "Device managed",
       "The device asks for firmware when it suits it. Its deployment group still decides which firmware."},
      {:off, "Off", "The device takes no firmware except what someone sends it by hand."}
    ]
  end

  @doc false
  def update_mode_icon(:automatic), do: "lucide-refresh-cw--light"
  def update_mode_icon(:device_managed), do: "lucide-cpu--light"
  def update_mode_icon(:off), do: "lucide-circle-slash--light"

  @doc false
  def update_mode_color(:automatic), do: "text-success"
  def update_mode_color(:device_managed), do: "text-base-300"
  def update_mode_color(:off), do: "text-alert"

  @doc false
  def update_mode_label(mode) do
    {_mode, label, _description} = Enum.find(update_modes(), &(elem(&1, 0) == mode))
    label
  end

  defp toggle_update_mode_menu(js \\ %JS{}) do
    JS.toggle(js,
      to: "#update-mode-menu-container",
      in: {"ease-out duration-150", "opacity-0", "opacity-100"},
      out: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end

  # Only ever closes, so Escape and click-away cannot open it the way JS.toggle
  # would, and are no-ops when it is already closed.
  defp hide_update_mode_menu(js \\ %JS{}) do
    JS.hide(js,
      to: "#update-mode-menu-container",
      transition: {"ease-out duration-150", "opacity-100", "opacity-0"}
    )
  end
end
