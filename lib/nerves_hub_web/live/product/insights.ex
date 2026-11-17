defmodule NervesHubWeb.Live.Product.Insights do
  use NervesHubWeb, :live_view

  import NervesHubWeb.Components.Fleet, only: [delimited: 1]
  import NervesHubWeb.CoreComponents, only: [switch: 1]

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Health
  alias NervesHub.Devices.Updates
  alias NervesHub.Helpers.RelativeTime
  alias NervesHub.Insights
  alias NervesHub.Insights.Trends
  alias NervesHub.ProductNotifications
  alias NervesHub.Products
  alias NervesHubWeb.Components.FleetComposition
  alias NervesHubWeb.Components.FleetTrends
  alias NervesHubWeb.Mounts.RequireEveryDevice

  on_mount(RequireEveryDevice)

  # The lists under the charts are "look at these" lists, not indexes: past a
  # few rows the link to the full list is the better answer.
  @failing_updates_list_size 3
  @notifications_list_size 3
  @flapping_list_size 5

  @impl Phoenix.LiveView
  def mount(_params, _session, %{assigns: %{current_scope: scope}} = socket) do
    product = Products.load_shared_secret_auth(scope.product)

    socket
    |> assign(:product, product)
    |> assign(:devices_path, ~p"/org/#{scope.org}/#{scope.product}/devices")
    |> assign(:composition_unit, :count)
    |> assign(:trends_period, "14d")
    |> assign(:adoption_view, :stacked)
    |> assign(:release_annotations, true)
    |> update_information()
    |> assign_notifications()
    |> maybe_assign_flapping()
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

  def handle_event("set-trends-period", %{"value" => period}, socket) do
    if period in Trends.periods() do
      socket
      |> assign(:trends_period, period)
      |> maybe_assign_trends()
      |> noreply()
    else
      noreply(socket)
    end
  end

  def handle_event("set-adoption-view", %{"value" => view}, socket) when view in ~w(stacked lines) do
    socket
    |> assign(:adoption_view, String.to_existing_atom(view))
    |> noreply()
  end

  def handle_event("toggle-release-annotations", _params, socket) do
    socket
    |> update(:release_annotations, &(!&1))
    |> noreply()
  end

  def handle_event("set-composition-unit", %{"unit" => unit}, socket) when unit in ~w(count percent) do
    socket
    |> assign(:composition_unit, String.to_existing_atom(unit))
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
    product = scope.product

    socket
    |> assign(:polling_pid, polling_pid)
    |> assign(:updated_at, DateTime.utc_now())
    |> assign_composition(product)
    |> assign_failing_updates()
    |> maybe_assign_trends()
  end

  # PostgreSQL alone, like the failing updates below, so the composition shows
  # whether or not the deployment runs analytics. One query, rerun on every
  # poll.
  defp assign_composition(socket, product) do
    composition = Insights.composition(product)

    socket
    |> assign(:composition, composition)
    |> assign(:fleet_size, composition.total)
    |> assign(:version_rows, Insights.versions(composition))
    |> assign(:stands_out, Insights.stands_out(composition))
  end

  # Only on the connected mount: the dead render has no client time zone to
  # bucket days in, and would run the ClickHouse queries twice per page load.
  # Rerun with every poll, so the charts end on the figures above them.
  defp maybe_assign_trends(%{assigns: %{current_scope: scope}} = socket) do
    if connected?(socket) and Application.get_env(:nerves_hub, :analytics_enabled) and socket.assigns.fleet_size > 0 do
      trends =
        Trends.trends(scope.product, socket.assigns.composition, socket.assigns.trends_period, socket.assigns.time_zone)

      assign(socket, :trends, trends)
    else
      assign(socket, :trends, nil)
    end
  end

  # PostgreSQL alone, so unlike the charts above this list is there whether
  # or not the deployment runs analytics. A device failing to take its firmware is
  # an operational fact rather than a statistic, and the count beside it has to
  # be exact. See `NervesHub.Devices.UpdateHistory`.
  defp assign_failing_updates(%{assigns: %{current_scope: scope}} = socket) do
    socket
    |> assign(:failing_devices, Updates.failing_updates(scope.product, @failing_updates_list_size))
    |> assign(:failing_count, Updates.failing_updates_count(scope.product))
  end

  # Connections and health flapping in one list, the busiest first. Both come
  # from ClickHouse, so the list is only there where analytics is.
  defp maybe_assign_flapping(%{assigns: %{current_scope: scope}} = socket) do
    if Application.get_env(:nerves_hub, :analytics_enabled) do
      connections =
        for {device, count} <- Connections.flapping_connections(scope.product) do
          %{
            device: device,
            kind: "connection",
            count: count,
            path: ~p"/org/#{scope.org}/#{scope.product}/devices/#{device.identifier}"
          }
        end

      health =
        for {device, count} <- Health.flapping_health(scope.product) do
          %{
            device: device,
            kind: "health",
            count: count,
            path: ~p"/org/#{scope.org}/#{scope.product}/devices/#{device.identifier}/health"
          }
        end

      flapping =
        (connections ++ health)
        |> Enum.sort_by(& &1.count, :desc)
        |> Enum.take(@flapping_list_size)

      socket
      |> assign(:flapping, flapping)
      |> assign(:flapping_enabled, true)
    else
      assign(socket, :flapping_enabled, false)
    end
  end

  defp assign_notifications(%{assigns: %{current_scope: scope}} = socket) do
    {notifications, result_meta} = ProductNotifications.paginated_list(scope.product, 1, @notifications_list_size)

    socket
    |> assign(:notifications, notifications)
    |> assign(:notification_count, result_meta.total_count)
  end

  @doc """
  How long the device has been failing, in the failing updates list's short
  form: minutes under an hour, hours under a day, then days, each floored.

  The span runs from the first failure of the current run to now. The list
  answers "an afternoon or a fortnight?", which one unit does. A device whose
  run predates `first_update_failure_at` has no start to count from.
  """
  def failing_for(%{first_update_failure_at: nil}), do: "—"

  def failing_for(%{first_update_failure_at: started_at}) do
    short_span(DateTime.diff(DateTime.utc_now(), started_at, :second))
  end

  @doc """
  When a notification last happened, as the notifications list shows it:
  "now", minutes or hours on the same day, "Yesterday", then the date, with
  the year only when it isn't this one. Days follow `time_zone`.
  """
  def occurred(at, time_zone, now \\ DateTime.utc_now()) do
    {at, now} = in_zone(at, now, time_zone)
    seconds = DateTime.diff(now, at, :second)
    days = Date.diff(DateTime.to_date(now), DateTime.to_date(at))

    cond do
      seconds < 60 -> "now"
      days == 0 -> short_span(seconds)
      days == 1 -> "Yesterday"
      at.year == now.year -> Calendar.strftime(at, "%b %-d")
      true -> Calendar.strftime(at, "%b %-d, %Y")
    end
  end

  defp in_zone(at, now, time_zone) do
    with {:ok, at} <- DateTime.shift_zone(at, time_zone),
         {:ok, now} <- DateTime.shift_zone(now, time_zone) do
      {at, now}
    else
      _ -> {at, now}
    end
  end

  defp short_span(seconds) when seconds < 3600, do: "#{max(div(seconds, 60), 1)} min"
  defp short_span(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)} h"
  defp short_span(seconds), do: "#{div(seconds, 86_400)} d"

  defp devices_count(1), do: "1 device"
  defp devices_count(count), do: "#{delimited(count)} devices"

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:meta, :any, required: true, doc: "the figure or note at the right of the heading")
  slot(:inner_block, required: true)

  slot :footer do
    attr(:class, :any)
  end

  # One of the lists under the charts: a heading over a rule, then rows
  # divided by a lighter one, the last row without.
  defp list_column(assigns) do
    ~H"""
    <section id={@id} class="flex min-w-0 flex-1 flex-col text-xs">
      <div class="flex items-baseline justify-between gap-3 border-b border-line-default pb-2 sm:pb-2.5">
        <h2 class="text-sm/5 font-semibold text-content-strong sm:text-ui/4.5">{@title}</h2>
        <span class="text-content-faint">{@meta}</span>
      </div>
      <div class="flex flex-col [&>*:not(:last-child)]:border-b [&>*:not(:last-child)]:border-line-subtle">
        {render_slot(@inner_block)}
        <div :for={footer <- @footer} class={["flex items-center gap-3 pt-2.5 sm:py-2.25", footer[:class]]}>
          {render_slot(footer)}
        </div>
      </div>
    </section>
    """
  end

  attr(:navigate, :string, default: nil)
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  defp list_row(%{navigate: nil} = assigns) do
    ~H"""
    <div class={["flex h-10 items-center gap-2.5 sm:h-auto sm:gap-3 sm:py-2.25", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp list_row(assigns) do
    ~H"""
    <.link navigate={@navigate} class={["group flex h-10 items-center gap-2.5 hover:*:first:underline sm:h-auto sm:gap-3 sm:py-2.25", @class]}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  slot(:inner_block, required: true)

  defp list_empty(assigns) do
    ~H"""
    <p class="py-2.25 text-content-faint">{render_slot(@inner_block)}</p>
    """
  end

  attr(:id, :string, required: true)
  attr(:updated_at, DateTime, required: true)

  defp updated_at(assigns) do
    ~H"""
    <span class="shrink-0 text-xs text-content-faint">
      Updated
      <time id={@id} phx-hook="UpdatingTimeAgo" datetime={DateTime.to_iso8601(DateTime.truncate(@updated_at, :second))}>
        {RelativeTime.from_now(@updated_at)}
      </time>
    </span>
    """
  end

  defp onboarding_nhl_host() do
    Application.get_env(:nerves_hub, :devices_websocket_url) || URI.parse(NervesHubWeb.Endpoint.url()).host
  end
end
