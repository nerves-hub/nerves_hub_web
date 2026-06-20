defmodule NervesHubWeb.Live.Product.Insights do
  use NervesHubWeb, :live_view

  alias NervesHub.Devices
  alias NervesHub.ProductNotifications
  alias NervesHub.Products

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    product = Products.load_shared_secret_auth(scope.product)

    socket
    |> assign(:product, product)
    |> update_information()
    |> fleet_health_information()
    |> assign_notifications()
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
    Process.cancel_timer(polling_pid)

    socket
    |> assign(:polling_pid, nil)
    |> noreply()
  end

  @impl Phoenix.LiveView
  def handle_info(:poll_device_counts, socket) do
    socket
    |> update_information()
    |> noreply()
  end

  defp update_information(%{assigns: %{current_scope: scope}} = socket) do
    polling_pid = Process.send_after(self(), :poll_device_counts, to_timeout(minute: 1))

    socket
    |> assign(:polling_pid, polling_pid)
    |> assign(:updated_at, DateTime.utc_now())
    |> assign(:online_count, Devices.online_count(scope.product))
    |> assign(:offline_count, Devices.offline_count(scope.product))
    |> assign(:not_seen_in_7_days, Devices.not_seen_in_x_days_count(scope.product, 7))
    |> assign(:not_seen_in_14_days, Devices.not_seen_in_x_days_count(scope.product, 14))
    |> assign(:fleet_size, Devices.total_count(scope.product))
  end

  defp fleet_health_information(%{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:healthy_count, Devices.health_status_count(scope.product, :healthy))
    |> assign(:warning_count, Devices.health_status_count(scope.product, :warning))
    |> assign(:unhealthy_count, Devices.health_status_count(scope.product, :unhealthy))
    |> assign(:unknown_count, Devices.health_status_count(scope.product, :unknown))
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

  defp onboarding_nhl_host() do
    Application.get_env(:nerves_hub, :devices_websocket_url) || URI.parse(NervesHubWeb.Endpoint.url()).host
  end
end
