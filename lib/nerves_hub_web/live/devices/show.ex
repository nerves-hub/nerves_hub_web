defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :live_view

  alias NervesHub.Accounts.PubSub, as: AccessPubSub
  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Consoles
  alias NervesHub.DeviceEvents
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Devices.Pinning
  alias NervesHub.Devices.PubSub
  alias NervesHub.Devices.Updates
  alias NervesHub.ErrorReports
  alias NervesHub.Extensions
  alias NervesHub.Firmwares
  alias NervesHub.FirmwareUpdates
  alias NervesHub.Products
  alias NervesHubWeb.Components.DevicePage.ActivityTab
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias NervesHubWeb.Components.DevicePage.DataHistoryTab
  alias NervesHubWeb.Components.DevicePage.DetailsTab
  alias NervesHubWeb.Components.DevicePage.ErrorsTab
  alias NervesHubWeb.Components.DevicePage.FirmwareHistoryTab
  alias NervesHubWeb.Components.DevicePage.Header
  alias NervesHubWeb.Components.DevicePage.HealthTab
  alias NervesHubWeb.Components.DevicePage.LocalShellTab
  alias NervesHubWeb.Components.DevicePage.LogsTab
  alias NervesHubWeb.Components.DevicePage.SettingsTab
  alias NervesHubWeb.Components.UpdateProgress
  alias NervesHubWeb.Presence
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
    SettingsTab
  ]

  @decorate requires_membership()
  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{current_scope: %{org: org, product: product, user: user} = scope} = socket.assigns

    device = load_device(scope, device_identifier)

    if connected?(socket) do
      Logger.metadata(device_id: device.id, user_id: user.id, product_id: product.id)
      PubSub.subscribe(device.id)
      AccessPubSub.subscribe_device_access(device.id)
      Consoles.PubSub.subscribe_console_watcher(device.id)
      Extensions.PubSub.subscribe_reports(device.id)
      Products.PubSub.subscribe(product.id)
      schedule_sleep_clock()
    end

    socket
    |> assign(%{org: org, product: product, user: user})
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> sidebar_tab(:devices)
    |> selected_tab()
    |> general_assigns(device)
    |> watch_paced_extensions()
    |> load_inprogress_firmware_update()
    |> assign(:pinned?, Pinning.device_pinned?(user.id, device.id))
    |> load_error_issue_count(product, device)
    |> assign(:sleep_clock, DateTime.utc_now())
    |> setup_presence_tracking()
    |> setup_tab_components(@tab_components)
    |> ok()
  end

  @decorate requires_membership()
  def handle_params(_params, _uri, socket) do
    socket
    |> update_tab_component_hooks()
    |> noreply()
  end

  # A sleeping device's "back in 5 minutes", and its turn to overdue, follow
  # the clock rather than any message, so the header is redrawn while the
  # device is asleep. Awake, the tick changes nothing and nothing is sent.
  def handle_info(:sleep_clock, socket) do
    schedule_sleep_clock()

    if DeviceConnection.sleep_state(socket.assigns.device_connection) do
      {:noreply, assign(socket, :sleep_clock, DateTime.utc_now())}
    else
      {:noreply, socket}
    end
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

    socket
    |> assign(:device_connection, Connections.get_latest_for_device(device.id))
    |> assign(:sleep_clock, DateTime.utc_now())
    |> noreply()
  end

  def handle_info(%Broadcast{event: "connection:change", payload: payload}, socket) do
    %{device: previous_device, current_scope: scope} = socket.assigns

    device = load_device(scope, previous_device.identifier)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
    # The clock only ticks while the device is asleep, so a device that has
    # just gone to sleep is judged from now, not from the last tick.
    |> assign(:sleep_clock, DateTime.utc_now())
    |> load_inprogress_firmware_update()
    |> then(fn socket ->
      if(payload.status == "online", do: clear_flash(socket), else: socket)
    end)
    |> maybe_send_metadata_updated_message(previous_device)
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
    |> then(&if(&1.assigns.inflight_version, do: &1, else: load_inprogress_firmware_update(&1)))
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

  # The device's tags changed, so a role limited to tagged devices may no
  # longer see it. Leaving the page also closes any console or shell open in
  # it. A change to the user's role remounts the page instead (see
  # `NervesHub.Accounts.PubSub`).
  def handle_info({:device_access_changed, _device_id}, %{assigns: %{current_scope: scope, device: device}} = socket) do
    case Devices.get_by_identifier(scope, device.identifier) do
      {:ok, _device} -> {:noreply, socket}
      {:error, :not_found} -> leave_device(socket, ~p"/org/#{scope.org}/#{scope.product}/devices")
    end
  end

  # Ignore unknown messages
  def handle_info(_unknown, socket), do: {:noreply, socket}

  @decorate requires_membership()
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

  @decorate requires_membership()
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

  @decorate requires_permission(:"device:reboot")
  def handle_event("reboot", _value, socket) do
    %{user: user, device: device} = socket.assigns

    DeviceEvents.reboot(device, user)

    {:noreply, put_flash(socket, :info, "Device reboot requested")}
  end

  @decorate requires_permission(:"device:reconnect")
  def handle_event("reconnect", _value, socket) do
    %{user: user, device: device} = socket.assigns

    DeviceTemplates.audit_request_action(user, device, :reconnect)

    :ok = DeviceEvents.reconnect(device)

    {:noreply, put_flash(socket, :info, "Device reconnection requested")}
  end

  @decorate requires_permission(:"device:identify")
  def handle_event("identify", _value, socket) do
    %{user: user, device: device} = socket.assigns

    DeviceEvents.identify(device, user)

    {:noreply, put_flash(socket, :info, "Device identification requested")}
  end

  @decorate requires_permission(:"device:clear-penalty-box")
  def handle_event("clear-penalty-box", _params, socket) do
    %{user: user, device: device} = socket.assigns

    {:ok, updated_device} = Updates.clear_penalty_box(device, user)

    socket
    |> assign(:device, updated_device)
    |> put_flash(:info, "Device removed from the penalty box, and firmware updates enabled.")
    |> noreply()
  end

  @decorate requires_permission(:"device:toggle-updates")
  def handle_event("set-update-mode", %{"mode" => mode}, socket) do
    %{user: user, device: device} = socket.assigns

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

  @decorate requires_permission(:"device:restore")
  def handle_event("restore", _, socket) do
    {:ok, device} = Devices.restore_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  @decorate requires_permission(:"device:destroy")
  def handle_event("destroy", _, socket) do
    %{org: org, product: product, device: device} = socket.assigns

    {:ok, _device} = Devices.destroy_device(device)

    socket
    |> put_flash(:info, "Device destroyed successfully.")
    |> push_navigate(to: ~p"/org/#{org}/#{product}/devices")
    |> noreply()
  end

  @decorate requires_permission(:"device:delete")
  def handle_event("delete", _, socket) do
    {:ok, device} = Devices.delete_device(socket.assigns.device)

    {:noreply, assign(socket, :device, device)}
  end

  @decorate requires_membership()
  def handle_event("set-deployment-group", %{"deployment_id" => ""}, socket) do
    socket
    |> put_flash(:error, "Please select a deployment group.")
    |> noreply()
  end

  def handle_async(:error_issue_count, {:ok, count}, socket) do
    {:noreply, assign(socket, :error_issue_count, count)}
  end

  def handle_async(:error_issue_count, {:exit, reason}, socket) do
    Logger.warning("Couldn't count the device's error report issues: #{inspect(reason)}")

    {:noreply, socket}
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
      :network_identities
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
        |> assign(:inflight_version, nil)
        |> assign(:inflight_started_at, nil)
        |> assign(:inflight_firmware_uuid, nil)

      inflight_update ->
        socket
        |> assign(:firmware_update_progress, inflight_update.progress)
        # A string, as progress reports carry it.
        |> assign(:firmware_update_stage, to_string(inflight_update.status))
        |> assign(:inflight_version, inflight_version(socket.assigns.product, inflight_update))
        |> assign(:inflight_started_at, inflight_update.inserted_at)
        |> assign(:inflight_firmware_uuid, inflight_update.firmware_uuid)
    end
  end

  # The version an update is taking the device to, for the firmware fact in
  # the header. Looked up once, when the update is found, not on each progress
  # report.
  defp inflight_version(product, inflight_update) do
    case Firmwares.get_firmware_by_product_and_uuid(product, inflight_update.firmware_uuid) do
      {:ok, firmware} -> firmware.version
      _not_found -> nil
    end
  end

  # The tabs from the left, as `{key, label, path, opts}`. Console and System
  # Shell dim while the device is offline, since neither has anything to show
  # until it connects, and Health carries a dot while the device's health
  # profile has engaged.
  @doc false
  def device_tabs(assigns) do
    %{org: org, product: product, device: device, device_connection: connection} = assigns
    base = ~p"/org/#{org}/#{product}/devices/#{device}"
    offline? = disconnected?(connection)

    [
      {:details, "Details", base, []},
      {:health, "Health", base <> "/health", [dot: health_engaged?(device)]},
      {:firmware_history, "Firmware History", base <> "/firmware_history", []},
      {:console, "Console", base <> "/console", [dimmed: offline?]},
      {:local_shell, "System Shell", base <> "/local_shell", [dimmed: offline?]},
      {:logs, "Logs", base <> "/logs", []},
      {:errors, "Errors", base <> "/errors", [count: nonzero(assigns[:error_issue_count])]},
      {:activity, "Activity", base <> "/activity", []}
    ]
  end

  @doc false
  def device_end_tabs(assigns) do
    %{org: org, product: product, device: device} = assigns
    base = ~p"/org/#{org}/#{product}/devices/#{device}"

    [
      {:data_history, "Data History", base <> "/data_history", []},
      {:settings, "Settings", base <> "/settings", []}
    ]
  end

  # The Errors tab's count: the issues the device reported in the last 30
  # days, or nothing where error reports can't be shown. The Errors tab keeps
  # it current while it is open.
  #
  # It is read from ClickHouse once the socket connects, off the mount, so a
  # slow or unreachable ClickHouse leaves the count empty rather than holding
  # up or failing every tab.
  defp load_error_issue_count(socket, product, device) do
    socket = assign(socket, :error_issue_count, nil)

    if connected?(socket) and error_issue_count?(product, device) do
      start_async(socket, :error_issue_count, fn -> ErrorReports.issue_count_for_device(device) end)
    else
      socket
    end
  end

  # Matches the Errors tab's own gating: on for the product, not turned off for
  # the device, and analytics on.
  defp error_issue_count?(%{extensions: %{error_reports: true}}, %{extensions: %{error_reports: false}}), do: false
  defp error_issue_count?(%{extensions: %{error_reports: true}}, _device), do: analytics_enabled?() == true
  defp error_issue_count?(_product, _device), do: false

  defp nonzero(count) when is_integer(count) and count > 0, do: count
  defp nonzero(_count), do: nil

  defp health_engaged?(%{latest_health: %{status: status}}) when status in [:warning, :unhealthy], do: true
  defp health_engaged?(_device), do: false

  defp setup_presence_tracking(%{assigns: %{device: device, user: user}} = socket) do
    topic = "device-#{device.identifier}"
    socket = stream(socket, :presences, [])

    with true <- connected?(socket),
         {:ok, _} <-
           Presence.track_user(topic, user.id, %{
             name: user.name,
             profile_picture_url: user.profile_picture_url
           }),
         :ok <- Presence.subscribe(topic) do
      stream(socket, :presences, Presence.list_present_users(topic))
    else
      _ ->
        socket
    end
  end

  # Tells the device's extensions channel that somebody is looking, which is the
  # whole of the page's involvement in reporting: the pace, and the `check`
  # itself, belong to the extension. Every open page used to run its own timer
  # and ask the device directly, so two people on one device meant two extra
  # streams of requests on top of the platform's.
  #
  # Both paced extensions are announced, each only if it is switched on for this
  # device -- a device running `metrics` and a device running `health` both get
  # to speed up while the page is open, and a device running both is asked once
  # by each rather than twice by either.
  #
  # There is nothing to give up again: watching lasts as long as this process,
  # and the reporting slows back down once the last page has closed.
  defp watch_paced_extensions(socket) do
    %{device: device, product: product} = socket.assigns

    _ =
      if connected?(socket) do
        [:health, :metrics]
        |> Enum.filter(&extension_enabled?(product, device, &1))
        |> Enum.each(&(:ok = Extensions.PubSub.watch(device.id, &1)))
      end

    socket
  end

  defp extension_enabled?(product, device, extension) do
    product.extensions[extension] and device.extensions[extension]
  end

  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end

  @sleep_clock_interval to_timeout(second: 30)

  defp schedule_sleep_clock() do
    _ = Process.send_after(self(), :sleep_clock, @sleep_clock_interval)
    :ok
  end

  defp general_assigns(socket, device) do
    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
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
  def update_mode_icon(:automatic), do: "lucide-refresh-cw"
  def update_mode_icon(:device_managed), do: "lucide-cpu"
  def update_mode_icon(:off), do: "lucide-circle-slash"

  @doc false
  def update_mode_color(:automatic), do: "text-success"
  def update_mode_color(:device_managed), do: "text-content-body"
  def update_mode_color(:off), do: "text-alert"

  @doc false
  def update_mode_label(mode) do
    {_mode, label, _description} = Enum.find(update_modes(), &(elem(&1, 0) == mode))
    label
  end

  defp leave_device(socket, path) do
    socket
    |> put_flash(:error, "You no longer have access to this device.")
    |> push_navigate(to: path)
    |> noreply()
  end
end
