defmodule NervesHubWeb.Live.Product.Insights do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.ProductNotifications
  alias NervesHub.Products

  @graph_periods ~w(twenty_four_hours fourteen_days four_weeks)

  # A donut is only readable at a glance with a handful of colours, so the
  # long tail of versions is folded into a single "Other" slice past this.
  @firmware_version_slices 6

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    product = Products.load_shared_secret_auth(scope.product)

    socket
    |> assign(:product, product)
    |> update_information()
    |> maybe_assign_device_connections_graph()
    |> assign_firmware_version_distribution()
    |> fleet_health_information()
    |> assign_notifications()
    |> maybe_assign_flapping_connections()
    |> maybe_assign_flapping_health()
    |> assign(:page_title, "#{scope.product.name} Insights")
    |> sidebar_tab(:insights)
    |> ok()
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-auto-refresh", _params, %{assigns: %{polling_pid: nil}} = socket) do
    socket
    |> update_information()
    |> noreply()
  end

  def handle_event("toggle-auto-refresh", _params, %{assigns: %{polling_pid: polling_pid}} = socket) do
    _ = Process.cancel_timer(polling_pid)

    socket
    |> assign(:polling_pid, nil)
    |> noreply()
  end

  def handle_event("select-graph-time-period", %{"period" => period}, socket) when period in @graph_periods do
    socket
    |> maybe_assign_device_connections_graph(String.to_existing_atom(period))
    |> noreply()
  end

  def handle_event("select-graph-time-period", _params, socket) do
    socket
    |> put_flash(:error, "Invalid graph period selected")
    |> noreply()
  end

  def handle_event(
        "view-devices-with-firmware-version",
        %{"version" => version},
        %{assigns: %{current_scope: scope, firmware_version_slices: slices}} = socket
      ) do
    if Enum.any?(slices, &(&1.filter == version)) do
      socket
      |> push_navigate(to: ~p"/org/#{scope.org}/#{scope.product}/devices?firmware_version=#{version}")
      |> noreply()
    else
      noreply(socket)
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:poll_device_counts, socket) do
    socket
    |> update_information()
    |> noreply()
  end

  defp update_information(%{assigns: %{current_scope: scope}} = socket) do
    polling_pid = Process.send_after(self(), :poll_device_counts, to_timeout(minute: 1))
    product = scope.product

    socket
    |> assign(:polling_pid, polling_pid)
    |> assign(:updated_at, DateTime.utc_now())
    |> assign(:fleet_size, Devices.total_count(product))
    |> assign_async(:online_count, fn -> {:ok, %{online_count: Devices.online_count(product)}} end)
    |> assign_async(:offline_count, fn -> {:ok, %{offline_count: Devices.offline_count(product)}} end)
    |> assign_async(:not_seen_in_7_days, fn ->
      {:ok, %{not_seen_in_7_days: Devices.not_seen_in_x_days_count(product, 7)}}
    end)
    |> assign_async(:not_seen_in_14_days, fn ->
      {:ok, %{not_seen_in_14_days: Devices.not_seen_in_x_days_count(product, 14)}}
    end)
  end

  @impl Phoenix.LiveView
  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp maybe_assign_device_connections_graph(socket, period \\ :fourteen_days)

  defp maybe_assign_device_connections_graph(%{assigns: %{current_scope: scope}} = socket, period) do
    # Only load graph data on the connected mount: the disconnected (dead) render
    # has no client timezone yet, and we'd otherwise run the ClickHouse queries
    # twice on every page load.
    if connected?(socket) and Application.get_env(:nerves_hub, :analytics_enabled) do
      {from, to, unit, data} = device_connections_graph(scope, socket.assigns.time_zone, period)

      socket
      |> assign(:device_connections_graph_enabled, true)
      |> assign(:device_connections_graph_from, from)
      |> assign(:device_connections_graph_to, to)
      |> assign(:device_connections_graph_unit, unit)
      |> assign(:device_connections_graph_data, data)
      |> assign(:connected_devices_period, period)
    else
      assign(socket, :device_connections_graph_enabled, false)
    end
  end

  defp device_connections_graph(scope, time_zone, :twenty_four_hours) do
    {time_zone, now} = local_now(time_zone)

    # Snap the window to the top of the (local) hour so the chart's axis bounds
    # line up with the hourly buckets (aligned via `toStartOfHour`), letting the
    # bars sit flush against both edges.
    to = %{now | minute: 0, second: 0, microsecond: {0, 0}}
    from = DateTime.add(to, -24, :hour)
    data = Connections.device_connections_by_hour(scope.org.id, scope.product.id, from, to, time_zone)

    {from, to, "hour", data}
  end

  defp device_connections_graph(scope, time_zone, :four_weeks),
    do: device_connections_graph_by_day(scope, time_zone, 28)

  defp device_connections_graph(scope, time_zone, :fourteen_days),
    do: device_connections_graph_by_day(scope, time_zone, 14)

  defp device_connections_graph_by_day(scope, time_zone, days) do
    {time_zone, now} = local_now(time_zone)

    to = DateTime.to_date(now)
    from = Date.add(to, -days)
    data = Connections.device_connections_by_date(scope.org.id, scope.product.id, from, to, time_zone)

    {from, to, "day", data}
  end

  # Resolves the viewer's "now" in their timezone, falling back to UTC if the
  # timezone name isn't recognised. Returns the (validated) timezone alongside,
  # so the same name is handed to the ClickHouse bucketing functions.
  defp local_now(time_zone) do
    case DateTime.now(time_zone) do
      {:ok, now} -> {time_zone, now}
      {:error, _} -> {"Etc/UTC", DateTime.utc_now()}
    end
  end

  defp maybe_assign_flapping_health(%{assigns: %{current_scope: scope}} = socket) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      socket
      |> assign(:flapping_health, Health.flapping_health(scope.product))
      |> assign(:flapping_health_enabled, true)
    else
      assign(socket, :flapping_health_enabled, false)
    end
  end

  defp maybe_assign_flapping_connections(%{assigns: %{current_scope: scope}} = socket) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      connections = Connections.flapping_connections(scope.product)

      socket
      |> assign(:flapping_connections, connections)
      |> assign(:flapping_connections_enabled, true)
    else
      assign(socket, :flapping_connections_enabled, false)
    end
  end

  defp assign_firmware_version_distribution(%{assigns: %{current_scope: scope}} = socket) do
    counts = Devices.firmware_version_counts(scope.product)
    slices = firmware_version_slices(counts)

    socket
    |> assign(:firmware_version_slices, slices)
    |> assign(:firmware_version_other, Enum.find(slices, &is_nil(&1.filter)))
    |> assign(:firmware_version_count, Enum.count(counts, &(&1.version != nil)))
    |> assign(:firmware_version_total, Enum.sum_by(counts, & &1.count))
  end

  # Turns the raw per-version counts into the slices the donut draws: at most
  # `@firmware_version_slices` named versions, with anything past that folded
  # into a trailing "Other" (`filter: nil`, because there's no single version
  # to send the devices list). `filter` is otherwise the devices list's
  # `firmware_version` filter value.
  defp firmware_version_slices(counts) do
    slices =
      Enum.map(counts, fn
        %{version: nil, count: count} -> %{label: "Unknown", filter: "Unknown", count: count}
        %{version: version, count: count} -> %{label: version, filter: version, count: count}
      end)

    case Enum.split(slices, @firmware_version_slices) do
      {slices, []} ->
        slices

      # a lone leftover reads better as itself than as an "Other" of one
      {slices, [only]} ->
        slices ++ [only]

      {slices, rest} ->
        folded = %{label: "Other", filter: nil, count: Enum.sum_by(rest, & &1.count), versions: length(rest)}
        slices ++ [folded]
    end
  end

  defp fleet_health_information(%{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:healthy_count, Health.health_status_count(scope.product, :healthy))
    |> assign(:warning_count, Health.health_status_count(scope.product, :warning))
    |> assign(:unhealthy_count, Health.health_status_count(scope.product, :unhealthy))
    |> assign(:unknown_count, Health.health_status_count(scope.product, :unknown))
    |> then(fn %{assigns: assigns} = socket ->
      total = assigns.healthy_count + assigns.warning_count + assigns.unhealthy_count + assigns.unknown_count
      assign(socket, :total_health_count, total)
    end)
  end

  defp assign_notifications(%{assigns: %{current_scope: scope}} = socket) do
    {notifications, result_meta} = ProductNotifications.paginated_list(scope.product, 1, 5)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notification_count, result_meta.total_count)
  end

  @doc """
  Returns `count` as a whole-number percentage of `total`, guarding against
  division by zero when there are no devices (or no health records).
  """
  def percentage(_count, total) when total in [0, nil], do: 0
  def percentage(count, total), do: round(count / total * 100)

  @doc """
  The colour token for the donut slice in position `index`, matching the
  palette the chart hook reads off the document root.
  """
  def firmware_version_color(index), do: "var(--color-chart-#{index + 1})"

  defp onboarding_nhl_host() do
    Application.get_env(:nerves_hub, :devices_websocket_url) || URI.parse(NervesHubWeb.Endpoint.url()).host
  end
end
