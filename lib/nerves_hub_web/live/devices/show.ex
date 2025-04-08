defmodule NervesHubWeb.Live.Devices.Show do
  use NervesHubWeb, :updated_live_view

  require Logger

  alias NervesHub.AuditLogs.DeviceTemplates
  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Extensions.Health
  alias NervesHub.Repo

  alias NervesHubWeb.Components.DevicePage.ActivityTab
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias NervesHubWeb.Components.DevicePage.DetailsTab
  alias NervesHubWeb.Components.DevicePage.HealthTab
  alias NervesHubWeb.Components.DevicePage.SettingsTab
  alias NervesHubWeb.Components.DeviceUpdateStatus
  alias NervesHubWeb.Components.FwupProgress

  alias NervesHubWeb.Presence

  alias Phoenix.Socket.Broadcast

  @tab_components [ActivityTab, ConsoleTab, DetailsTab, HealthTab, SettingsTab]

  def mount(%{"device_identifier" => device_identifier}, _session, socket) do
    %{org: org, product: product, user: user} = socket.assigns

    device = load_device(org, device_identifier)

    if connected?(socket) do
      socket.endpoint.subscribe("device:#{device.identifier}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}:internal")
      socket.endpoint.subscribe("device:console:#{device.id}")
      socket.endpoint.subscribe("device:#{device.id}:extensions")
      socket.endpoint.subscribe("firmware")
    end

    socket
    |> page_title("Device #{device.identifier} - #{product.name}")
    |> sidebar_tab(:devices)
    |> selected_tab()
    |> assign(:extension_overrides, extension_overrides(device, product))
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
    %{device: device, org: org} = socket.assigns

    {:ok, device} = Devices.get_device_by_identifier(org, device.identifier, :latest_connection)

    socket
    |> assign(:device, device)
    |> assign(:device_connection, device.latest_connection)
    |> noreply()
  end

  def handle_info(
        %Broadcast{event: "connection:status", payload: %{status: "online"}},
        %{assigns: %{device: device}} = socket
      ) do
    device =
      device
      |> Repo.reload()
      |> Repo.preload([:deployment_group, :latest_connection])

    {:noreply, general_assigns(socket, device)}
  end

  def handle_info(
        %Broadcast{event: "connection:status", payload: %{status: "offline"}},
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
    |> assign(:device_connection, device.latest_connection)
    |> assign(:fwup_progress, nil)
    |> assign(:update_information, Devices.resolve_update(device))
    |> then(fn socket ->
      if(payload.status == "online", do: clear_flash(socket), else: socket)
    end)
    |> noreply()
  end

  def handle_info(%Broadcast{event: "fwup_progress", payload: payload}, socket) do
    if payload.percent == 100 do
      socket
      |> send_toast(:info, "Update complete: The device will reboot shortly.")
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
        |> put_flash(
          :info,
          "Could not pin device. Please contact support."
        )
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
        |> put_flash(
          :info,
          "Could not unpin device. Please contact support."
        )
        |> noreply()
    end
  end

  def handle_event("reboot", _value, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:reboot", org_user)

    DeviceTemplates.audit_reboot(user, device)

    socket.endpoint.broadcast_from(self(), "device:#{device.id}", "reboot", %{})

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

    DeviceTemplates.audit_request_action(user, device, "identify itself")

    socket.endpoint.broadcast_from(self(), "device:#{socket.assigns.device.id}", "identify", %{})

    {:noreply, put_flash(socket, :info, "Device identification requested")}
  end

  def handle_event("clear-penalty-box", _params, socket) do
    %{org_user: org_user, user: user, device: device} = socket.assigns

    authorized!(:"device:clear-penalty-box", org_user)

    {:ok, updated_device} = Devices.clear_penalty_box(device, user)

    socket
    |> assign(:device, updated_device)
    |> send_toast(:info, "Device removed from the penalty box, and firmware updates enabled.")
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

    if connected?(socket) do
      {:ok, _} = Presence.track_user(topic, user.id, %{name: user.name})
      :ok = Presence.subscribe(topic)
      stream(socket, :presences, Presence.list_online_users(topic))
    else
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

  defp extension_overrides(device, product) do
    device.extensions
    |> Map.from_struct()
    |> Enum.filter(fn {extension, enabled} ->
      enabled == false and product.extensions[extension]
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp disconnected?(connection) do
    is_nil(connection) || connection.status != :connected
  end

  defp general_assigns(socket, device) do
    socket
    |> assign(:deployment_group, device.deployment_group)
    |> assign(:device_connection, device.latest_connection)
    |> assign(:device, device)
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

  # TODO: refactor to use tailwind attributes
  def tab_classes(tab_selected, tab) do
    if tab_selected == tab do
      "px-6 py-2 h-11 font-normal text-sm text-neutral-50 border-b border-indigo-500 bg-tab-selected relative -bottom-px"
    else
      "px-6 py-2 h-11 font-normal text-sm text-zinc-300 hover:border-b hover:border-indigo-500 relative -bottom-px"
    end
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
    <SettingsTab.render :if={@tab == :settings} {assigns} />
    """
  end
end
