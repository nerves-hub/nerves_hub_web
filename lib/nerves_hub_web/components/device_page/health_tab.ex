defmodule NervesHubWeb.Components.DevicePage.HealthTab do
  use NervesHubWeb, tab_component: :health

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Accounts
  alias NervesHub.Accounts.User.DisplayPreferences
  alias NervesHub.Devices.Alarms
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Metrics
  alias NervesHub.Helpers.RelativeTime
  alias NervesHub.Products
  alias NervesHub.Products.HealthProfiles
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.DeviceHealth.AlarmsRow
  alias NervesHubWeb.Components.DeviceHealth.MetricLabels
  alias NervesHubWeb.Components.DeviceHealth.StatusBadge
  alias NervesHubWeb.Components.Utils
  alias Phoenix.LiveView.AsyncResult

  @time_frame_opts [
    {"hour", 3},
    {"day", 1},
    {"day", 7}
  ]
  @default_time_frame {"hour", 3}

  @manual_metrics [
    "cpu_temp",
    "cpu_usage_percent",
    "mem_used_mb",
    "mem_size_mb",
    "mem_used_percent",
    "load_1min",
    "load_5min",
    "load_15min",
    "disk_used_percentage",
    "disk_total_kb",
    "disk_available_kb",
    "timestamp"
  ]

  @load_keys ["load_1min", "load_5min", "load_15min"]

  # Will not be rendered as chart: sizes that only qualify another metric.
  @no_chart_metrics [
    "mem_size_mb",
    "disk_total_kb",
    "disk_available_kb"
  ]

  # A chart that another one makes redundant, charted only when the device
  # doesn't report the one that replaces it: the 15 minute load average reads
  # as the trend the shorter ones are noise around, and memory as a share of
  # the total says what the megabytes do.
  @superseded_charts %{
    "load_1min" => "load_15min",
    "load_5min" => "load_15min",
    "mem_used_mb" => "mem_used_percent"
  }

  # The well-known metrics' chart titles, each with the unit or window shown
  # faintly beside it, in the order they're charted. Other metrics follow.
  @chart_titles %{
    "cpu_usage_percent" => {"CPU usage", "%"},
    "mem_used_percent" => {"Memory used", "%"},
    "mem_used_mb" => {"Memory used", "MB"},
    "disk_used_percentage" => {"Disk used", "%"},
    "cpu_temp" => {"CPU temperature", "°C"},
    "load_15min" => {"Load average", "15 min"},
    "load_5min" => {"Load average", "5 min"},
    "load_1min" => {"Load average", "1 min"}
  }

  @chart_order ~w(cpu_usage_percent mem_used_percent mem_used_mb disk_used_percentage cpu_temp load_15min load_5min load_1min)

  @tick_interval 55_000

  def tab_params(_params, _uri, socket) do
    profile = HealthProfiles.resolve(socket.assigns.device)

    socket
    |> schedule_tick()
    |> update_from_and_until_timestamps()
    |> assign(:time_frame_opts, @time_frame_opts)
    # The charts read ClickHouse; the numbers above them do not. Without a
    # ClickHouse the tab still has current values to show, so the tab stays and
    # the charts say why they are empty.
    |> assign(:analytics_enabled, analytics_enabled?())
    |> assign(:latest_metrics, Metrics.get_latest_metric_set(socket.assigns.device.id))
    |> assign(:health_profile, profile)
    |> assign(:threshold_specs, threshold_specs(profile))
    # Not `:alarms`, which the Details tab keeps and clears in its own
    # `cleanup/0`.
    |> assign(:health_alarms, Alarms.current_alarms_for_device(socket.assigns.device))
    |> assign(:custom_health_labels, Products.custom_health_metrics_labels(socket.assigns.product))
    |> assign(:editing_label_key, nil)
    |> assign(:chart_data, %{})
    |> assign(:has_chart_data, %{})
    |> assign(:offline_periods, [])
    |> assign(:zoom, nil)
    |> async_assign_charts()
    |> load_offline_periods()
    |> cont()
  end

  # `:analytics_enabled` is deliberately absent: the Logs, Errors and Data
  # History tabs set it too, and `cleanup/0` runs for every inactive tab -- a
  # shared key listed here is deleted out from under whichever tab is active.
  # See `NervesHubWeb.Components.DevicePage.TabCleanupTest`.
  def cleanup() do
    [
      :time_frame,
      :time_frame_opts,
      :charts,
      :chart_data,
      :has_chart_data,
      :custom_health_labels,
      :editing_label_key,
      :health_profile,
      :health_alarms,
      :offline_periods,
      :zoom
    ]
  end

  def hooked_async("load_chart:" <> key, {:ok, results}, socket) do
    socket
    |> put_chart_data(key, AsyncResult.ok(chart_data(socket, key), results))
    |> halt()
  end

  def hooked_async("load_chart:" <> key, {:exit, reason}, socket) do
    _ =
      Sentry.capture_message("Unexpected error when loading device health charts",
        extra: %{key: key, reason: reason},
        result: :none
      )

    socket
    |> put_chart_data(key, AsyncResult.failed(chart_data(socket, key), {:exit, reason}))
    |> halt()
  end

  def hooked_async("update_chart:" <> key, {:ok, results}, socket) do
    socket
    |> put_has_chart_data(key, Enum.any?(results))
    |> push_event("update-charts", Map.merge(%{key: key, data: results}, time_frame_bounds(socket)))
    |> halt()
  end

  def hooked_async("update_chart:" <> key, {:exit, reason}, socket) do
    _ =
      Sentry.capture_message("Unexpected error when updating device health charts",
        extra: %{key: key, reason: reason},
        result: :none
      )

    halt(socket)
  end

  def hooked_async("load_offline", {:ok, periods}, socket) do
    socket
    |> assign(:offline_periods, periods)
    |> push_event("offline-periods", %{periods: periods})
    |> halt()
  end

  # The charts are still worth showing without the offline spans.
  def hooked_async("load_offline", {:exit, reason}, socket) do
    _ =
      Sentry.capture_message("Unexpected error when loading device offline periods",
        extra: %{device_id: socket.assigns.device.id, reason: reason},
        result: :none
      )

    halt(socket)
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("set-time-frame", %{"unit" => unit, "amount" => amount}, socket) do
    {parsed_amount, ""} = Integer.parse(amount)

    socket
    |> assign(:time_frame, {validate_time_unit(unit), parsed_amount})
    |> assign(:zoom, nil)
    |> update_from_and_until_timestamps()
    |> update_charts()
    |> load_offline_periods()
    |> halt()
  end

  # Sent by the chart hook when a drag across a chart zooms them all, as unix
  # milliseconds, so the header can name the span and offer to undo it.
  def hooked_event("charts-zoomed", %{"from" => from, "until" => until}, socket)
      when is_number(from) and is_number(until) do
    zoom = {DateTime.from_unix!(round(from), :millisecond), DateTime.from_unix!(round(until), :millisecond)}

    socket
    |> assign(:zoom, zoom)
    |> halt()
  end

  def hooked_event("reset-zoom", _params, socket) do
    socket
    |> assign(:zoom, nil)
    |> update_from_and_until_timestamps()
    |> push_time_frame()
    |> halt()
  end

  def hooked_event("set-chart-style", %{"style" => style}, socket) do
    %{user: user, current_scope: scope} = socket.assigns

    case Accounts.update_user_health_chart_style(user, style) do
      {:ok, user} ->
        socket
        |> assign(:user, user)
        |> assign(:current_scope, %{scope | user: user})
        |> push_event("chart-style", %{style: DisplayPreferences.health_chart_style(user.display_preferences)})
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Your chart style couldn't be saved. Please reload the page and try again.")
        |> halt()
    end
  end

  def hooked_event("edit-health-label", %{"key" => key}, socket) do
    socket
    |> assign(:editing_label_key, key)
    |> halt()
  end

  def hooked_event("cancel-health-label", _params, socket) do
    socket
    |> assign(:editing_label_key, nil)
    |> halt()
  end

  def hooked_event("save-health-label", %{"key" => key, "label" => label}, socket) do
    authorized!(:"product:update", socket.assigns.current_scope)

    %{product: product} = socket.assigns

    case Products.set_custom_health_metrics_label(product, key, label) do
      {:ok, _} ->
        socket
        |> assign(:custom_health_labels, Products.custom_health_metrics_labels(product))
        |> assign(:editing_label_key, nil)
        |> halt()

      {:error, _changeset} ->
        socket
        |> put_flash(:error, "Could not update the metric label.")
        |> halt()
    end
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "health_check_report"}, %{assigns: %{device: device}} = socket) do
    latest_metrics = Metrics.get_latest_metric_set(device.id)

    chart_keys = metrics_to_chart(socket.assigns.latest_metrics)

    socket =
      socket
      |> update_from_and_until_timestamps()
      |> assign(:latest_metrics, latest_metrics)
      |> assign_metadata()

    bounds = time_frame_bounds(socket)

    # No charts yet, so this report is what creates them.
    if Enum.empty?(chart_keys) do
      seed_charts(socket, latest_metrics)
    else
      latest_metrics
      |> metrics_to_chart()
      |> Enum.reduce(socket, fn key, socket ->
        data = %{
          x: DateTime.to_unix(latest_metrics["timestamp"], :millisecond),
          y: latest_metrics[key]
        }

        socket
        |> push_event("add-data-point", Map.merge(%{key: key, data: data}, bounds))
        |> put_has_chart_data(key, true)
      end)
    end
    |> halt()
  end

  # Sent by `NervesHub.Devices.Alarms` whenever the device's raised set moves.
  def hooked_info(%Broadcast{event: "alarms:updated"}, %{assigns: %{device: device}} = socket) do
    socket
    |> assign(:health_alarms, Alarms.current_alarms_for_device(device))
    |> halt()
  end

  def hooked_info(:tick, socket) do
    socket
    |> schedule_tick()
    |> update_from_and_until_timestamps()
    |> push_time_frame()
    |> load_offline_periods()
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:health_enabled?, assigns.product.extensions.health && assigns.device.extensions.health)
      |> assign(:stale?, disconnected?(assigns.device_connection))
      |> assign(:engaged, StatusBadge.engaged_reasons(assigns.device.latest_health))

    ~H"""
    <div
      id="health-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content flex w-full flex-col gap-4 p-4 opacity-0 transition-all duration-500 sm:p-6 phx-click-loading:opacity-50"
    >
      <section id="health-now" class={card_class()}>
        <div class="flex min-h-12 flex-wrap items-center justify-between gap-x-3.5 gap-y-1 px-4 py-2.5 sm:py-0">
          <div class="flex items-center gap-2.5">
            <h2 class="text-sm/4.5 font-semibold text-content-strong">Now</h2>
            <StatusBadge.render :if={@health_enabled? && Enum.any?(@latest_metrics)} health={@device.latest_health} stale?={@stale?} />
          </div>
          <div :if={@health_enabled? && Enum.any?(@latest_metrics)} class="flex flex-wrap items-center gap-x-3.5 gap-y-1 text-xs text-content-faint">
            <span :if={@latest_metrics["timestamp"]}>
              {if @stale?, do: "Last reported", else: "Updated"}
              <time id="health-last-updated" phx-hook="UpdatingTimeAgo" datetime={String.replace(DateTime.to_string(DateTime.truncate(@latest_metrics["timestamp"], :second)), " ", "T")}>
                {RelativeTime.from_now(@latest_metrics["timestamp"])}
              </time>
            </span>
            <span :if={@latest_metrics["timestamp"] && @health_profile} class="hidden h-3.5 w-px bg-line-default sm:block" aria-hidden="true"></span>
            <span :if={@health_profile} class="text-content-muted">
              Thresholds from
              <.link
                navigate={~p"/org/#{@org}/#{@product}/settings/health"}
                class="font-medium text-content-strong underline decoration-1 underline-offset-3 hover:decoration-content-muted"
              >
                {profile_name(@health_profile)}
              </.link>
            </span>
          </div>
        </div>

        <p :if={!@health_enabled?} class="px-4 pb-4 text-ui/4.5 text-content-muted">
          Reporting is not enabled {if(!@product.extensions.health, do: "for your product", else: "for your device")}.
          <.link class="underline decoration-line-strong underline-offset-4 hover:text-content-strong" href={health_docs()}>
            Learn more about device health and alert reporting.
          </.link>
        </p>

        <p :if={@health_enabled? && Enum.empty?(@latest_metrics)} class="px-4 pb-4 text-ui/4.5 text-content-muted">
          No health metrics have been received from the device.
          <.link class="underline decoration-line-strong underline-offset-4 hover:text-content-strong" href={health_docs()}>
            Learn more about device health reporting.
          </.link>
        </p>

        <div :if={@health_enabled? && Enum.any?(@latest_metrics)} class="grid grid-cols-[repeat(auto-fit,minmax(10rem,1fr))] items-start gap-x-8 gap-y-5 px-4 pt-1 pb-4.5">
          <.tile
            :for={tile <- tiles(@latest_metrics, @custom_health_labels)}
            tile={tile}
            spec={@threshold_specs[tile.key]}
            engaged={Enum.find(@engaged, fn {_level, key, _reason} -> key in tile.keys end)}
          />
        </div>

        <AlarmsRow.render :if={alarms_reported?(@product, @device)} id="health-alarms" alarms={@health_alarms} />
      </section>

      <section :if={Enum.any?(@latest_metrics)} id="health-history" class={card_class()}>
        <div class="flex min-h-13 flex-wrap items-center justify-between gap-x-3.5 gap-y-2 px-4 py-2.5 sm:py-0">
          <div class="flex items-baseline gap-2.5">
            <h2 class="text-sm/4.5 font-semibold text-content-strong">History</h2>
            <span :if={!@zoom} class="text-xs text-content-faint">{time_range(@charts_from_timestamp, @charts_until_timestamp, @time_zone)}</span>
            <span :if={@zoom} class="text-xs text-content-faint">{time_range(elem(@zoom, 0), elem(@zoom, 1), @time_zone)}</span>
          </div>
          <div class="flex items-center gap-3.5">
            <span :if={@analytics_enabled && !@zoom} class="hidden text-xs text-content-faint md:inline">Drag across a chart to zoom</span>
            <.button :if={@zoom} type="button" size="sm" phx-click="reset-zoom">
              <span class="lucide-zoom-out text-content-muted" aria-hidden="true"></span> Reset zoom
            </.button>
            <div role="group" aria-label="Chart style" class="flex h-7 overflow-clip rounded border border-line-default">
              <button
                :for={{style, icon, label} <- [{:line, "lucide-chart-spline", "Line"}, {:scatter, "lucide-chart-scatter", "Scatter"}]}
                type="button"
                phx-click="set-chart-style"
                phx-value-style={style}
                aria-pressed={to_string(style == DisplayPreferences.health_chart_style(@user.display_preferences))}
                aria-label={label}
                title={label}
                class="flex w-7.5 cursor-pointer items-center justify-center border-l border-line-default text-content-muted first:border-l-0 hover:text-content-strong aria-pressed:bg-surface-muted aria-pressed:text-content-strong"
              >
                <span class={[icon, "size-3.5"]} aria-hidden="true"></span>
              </button>
            </div>
            <div role="group" aria-label="Time frame" class="flex h-7 overflow-clip rounded border border-line-default">
              <button
                :for={{unit, amount} <- @time_frame_opts}
                type="button"
                phx-click="set-time-frame"
                phx-value-unit={unit}
                phx-value-amount={amount}
                aria-pressed={to_string({unit, amount} == @time_frame)}
                class="flex cursor-pointer items-center border-l border-line-default px-2.5 text-xs font-medium text-content-muted first:border-l-0 hover:text-content-strong aria-pressed:bg-surface-muted aria-pressed:text-content-strong"
              >
                {time_frame_label(unit, amount)}
              </button>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-x-8 px-4 pb-2 lg:grid-cols-2">
          <div :for={key <- metrics_to_chart(@latest_metrics)} id={"health-chart-#{key}"} class="flex min-w-0 flex-col gap-1.5 border-t border-line-subtle pt-3.5 pb-2">
            <div class="group/label flex min-h-5 items-center justify-between gap-3">
              <form :if={@editing_label_key == key} phx-submit="save-health-label" class="flex min-w-0 items-center gap-1.5">
                <input type="hidden" name="key" value={key} />
                <input
                  type="text"
                  name="label"
                  value={chart_title(key, @custom_health_labels)}
                  aria-label="Label"
                  phx-mounted={JS.focus()}
                  autocomplete="off"
                  maxlength="255"
                  class="h-6 min-w-0 rounded border border-line-control border-b-line-strong bg-surface-raised px-2 text-ui font-medium text-content-strong focus:border-line-control focus:ring-0 focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
                />
                <.button type="submit" size="sm" square aria-label="Save label">
                  <span class="lucide-check" aria-hidden="true"></span>
                </.button>
                <.button type="button" size="sm" square phx-click="cancel-health-label" aria-label="Cancel editing label">
                  <span class="lucide-x" aria-hidden="true"></span>
                </.button>
              </form>
              <div :if={@editing_label_key != key} class="flex min-w-0 items-baseline gap-1.5">
                <h3 class="truncate text-ui/5 font-medium text-content-strong">{chart_title(key, @custom_health_labels)}</h3>
                <span :if={chart_qualifier(key)} class="shrink-0 text-xs text-content-faint">{chart_qualifier(key)}</span>
                <code :if={show_key?(key, @custom_health_labels)} class="shrink-0 font-mono text-xs text-content-faint">{key}</code>
                <button
                  :if={authorized?(:"product:update", @current_scope)}
                  type="button"
                  phx-click="edit-health-label"
                  phx-value-key={key}
                  aria-label={"Edit label for #{chart_title(key, @custom_health_labels)}"}
                  class="flex cursor-pointer self-center text-content-faint opacity-0 transition-opacity group-hover/label:opacity-100 hover:text-content-strong focus-visible:opacity-100"
                >
                  <span class="lucide-pencil size-3.5" aria-hidden="true"></span>
                </button>
              </div>
              <div class="flex shrink-0 items-center gap-2 text-xs">
                <.chart_status key={key} value={@latest_metrics[key]} spec={@threshold_specs[key]} />
                <span :if={is_number(@latest_metrics[key])} class="text-ui/5 font-medium text-content-strong">
                  {with_unit(reading(key, @latest_metrics[key]), value_unit(key))}
                </span>
              </div>
            </div>
            <div class="relative h-39 w-full">
              <.async_result :let={chart_data} assign={@chart_data[key]}>
                <:loading>
                  <div class="absolute inset-0 flex items-center justify-center">
                    <span class="text-xs text-content-faint">Loading history…</span>
                  </div>
                </:loading>
                <:failed :let={_failure}>
                  <div class="absolute inset-0 flex items-center justify-center">
                    <span class="text-xs text-content-faint">Sorry, there was an error loading the history for {key}.</span>
                  </div>
                </:failed>
                <canvas
                  id={key <> "-chart"}
                  phx-hook="Chart"
                  phx-update="ignore"
                  data-key={key}
                  data-metrics={Jason.encode!(chart_data)}
                  data-thresholds={Jason.encode!(@threshold_specs[key])}
                  data-max={suggested_max(key)}
                  data-value-unit={value_unit(key)}
                  data-mintime={Jason.encode!(@charts_from_timestamp)}
                  data-maxtime={Jason.encode!(@charts_until_timestamp)}
                  data-time-unit={get_time_unit(@time_frame)}
                  data-offline={Jason.encode!(@offline_periods)}
                  data-chart-style={DisplayPreferences.health_chart_style(@user.display_preferences)}
                ></canvas>
                <div :if={!@has_chart_data[key] && Enum.empty?(chart_data)} class="absolute inset-0 flex items-center justify-center bg-surface-raised/80 px-6 text-center">
                  <span :if={@analytics_enabled} class="text-xs text-content-faint">No metrics for {key} found for the selected period.</span>
                  <span :if={!@analytics_enabled} class="text-xs text-content-faint">
                    Metric history needs analytics, which isn't enabled for your platform. The current values above are up to date.
                  </span>
                </div>
              </.async_result>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  defp card_class(),
    do: "flex flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card"

  # One reading in the Now card: a label, the value with its unit, a bar with
  # the thresholds marked on it for a percentage, and under that the
  # thresholds, or why the metric engaged in the level's colour.
  attr(:tile, :map, required: true)
  attr(:spec, :map, default: nil)
  attr(:engaged, :any, default: nil)

  defp tile(%{tile: %{kind: :load}} = assigns) do
    ~H"""
    <div id={"health-tile-#{@tile.id}"} class="flex min-w-0 flex-col gap-1.5">
      <span class="text-xs font-medium text-content-muted">{@tile.label}</span>
      <div class="flex h-7.5 items-baseline gap-3">
        <span class="w-12.5 shrink-0 text-2xl/7.5 font-medium tracking-[-0.02em] text-content-strong">{load_value(@tile.values["load_1min"])}</span>
        <span class="w-9.5 shrink-0 text-base font-medium text-content-body">{load_value(@tile.values["load_5min"])}</span>
        <span class="w-9.5 shrink-0 text-base font-medium text-content-body">{load_value(@tile.values["load_15min"])}</span>
      </div>
      <div class="flex h-4 items-center gap-3 text-xs text-content-faint">
        <span class="w-12.5 shrink-0">1 min</span><span class="w-9.5 shrink-0">5 min</span><span class="w-9.5 shrink-0">15 min</span>
      </div>
      <.tile_footnote spec={@spec} engaged={@engaged} prefix="15 min: " />
    </div>
    """
  end

  defp tile(assigns) do
    # The bar shows the reading, so it takes the colour of the threshold the
    # reading is past, as the chart's current value does.
    assigns = assign(assigns, :level, breach_level(assigns.tile.percent, assigns.spec))

    ~H"""
    <div id={"health-tile-#{@tile.id}"} class="flex min-w-0 flex-col gap-1.5">
      <span class="truncate text-xs font-medium text-content-muted">
        {@tile.label}<span :if={@tile.detail} class="font-normal"> · {@tile.detail}</span>
      </span>
      <div class="flex h-7.5 items-baseline gap-0.5">
        <span class="text-2xl/7.5 font-medium tracking-[-0.02em] text-content-strong">{@tile.value}</span>
        <span :if={@tile.unit} class="text-sm text-content-muted">{@tile.unit}</span>
      </div>
      <div :if={@tile.percent} class="relative flex h-4 items-center" aria-hidden="true">
        <div class={["flex h-1 grow rounded-full", level_track(@level)]}>
          <div class={["h-1 rounded-full", level_fill(@level)]} style={"width: #{clamp_percent(@tile.percent)}%"}></div>
        </div>
        <span
          :for={{level, threshold} <- bar_ticks(@spec)}
          class={["absolute top-0.75 h-2.5 w-0.5 rounded-[1px]", if(level == :alert, do: "bg-alert", else: "bg-warning")]}
          style={"left: #{threshold}%"}
        ></span>
      </div>
      <div :if={!@tile.percent} class="h-4"></div>
      <.tile_footnote spec={@spec} engaged={@engaged} unit={@tile.unit} prefix="" />
    </div>
    """
  end

  attr(:spec, :map)
  attr(:engaged, :any)
  attr(:unit, :string, default: nil)
  attr(:prefix, :string, default: "")

  defp tile_footnote(assigns) do
    ~H"""
    <%= cond do %>
      <% @engaged -> %>
        <span class={["text-xs", level_text(@engaged)]}>{breach_text(elem(@engaged, 2), @unit)}</span>
      <% @spec -> %>
        <span class="text-xs text-content-faint">{@prefix}{thresholds_text(@spec, @unit)}</span>
      <% true -> %>
        <span class="text-xs text-content-faint">No thresholds set</span>
    <% end %>
    """
  end

  # Beside a chart's current value: whether that reading is past a threshold
  # (judged on the reading alone, as the chart's band is), that the
  # thresholds sit above the chart's scale, or that a well-known metric has
  # none.
  attr(:key, :string, required: true)
  attr(:value, :any, required: true)
  attr(:spec, :map, default: nil)

  defp chart_status(assigns) do
    assigns = assign(assigns, :level, breach_level(assigns.value, assigns.spec))

    ~H"""
    <%= cond do %>
      <% @level -> %>
        <span class={["flex items-center gap-1.25 font-medium", if(@level == :alert, do: "text-alert-content", else: "text-warning-content")]}>
          <span class={["size-1.5 shrink-0 rounded-full", if(@level == :alert, do: "bg-alert", else: "bg-warning")]} aria-hidden="true"></span>
          {breach_label(@level, @spec)}
        </span>
      <% above_scale?(@key, @value, @spec) -> %>
        <span class="hidden text-content-faint sm:inline">
          Thresholds {Utils.format_number(@spec.warning)} and {Utils.format_number(@spec.alert)} are above this scale
        </span>
      <% !@spec && well_known?(@key) -> %>
        <span class="text-content-faint">No thresholds set</span>
      <% true -> %>
    <% end %>
    """
  end

  defp update_from_and_until_timestamps(socket) do
    {unit, unit_amount} = Map.get(socket.assigns, :time_frame, @default_time_frame)

    from = DateTime.add(DateTime.utc_now(), -unit_amount, String.to_existing_atom(unit))
    until = DateTime.utc_now()

    socket
    |> assign(:time_frame, {unit, unit_amount})
    |> assign(:charts_from_timestamp, from)
    |> assign(:charts_until_timestamp, until)
  end

  defp update_charts(socket) do
    %{device: device, time_frame: time_frame, latest_metrics: latest_metrics} = socket.assigns

    latest_metrics
    |> metrics_to_chart()
    |> Enum.reduce(socket, fn key, socket ->
      start_async(socket, "update_chart:#{key}", fn ->
        formatted_metrics(device, key, time_frame)
      end)
    end)
  end

  # When the device had no connection over the time frame, as
  # `[[from, until]]` in unix milliseconds, for the charts to shade. Connection
  # history lives in ClickHouse, so there's nothing to shade without it.
  defp load_offline_periods(%{assigns: %{analytics_enabled: false}} = socket), do: socket

  defp load_offline_periods(socket) do
    %{device: device, charts_from_timestamp: from, charts_until_timestamp: until} = socket.assigns

    start_async(socket, "load_offline", fn ->
      for {from, until} <- Connections.offline_periods(device, from, until) do
        [DateTime.to_unix(from, :millisecond), DateTime.to_unix(until, :millisecond)]
      end
    end)
  end

  defp async_assign_charts(socket) do
    device = socket.assigns.device
    time_frame = socket.assigns.time_frame

    socket.assigns.latest_metrics
    |> metrics_to_chart()
    |> Enum.reduce(socket, fn key, socket ->
      socket
      |> put_chart_data(key, AsyncResult.loading())
      |> put_has_chart_data(key, false)
      |> start_async("load_chart:#{key}", fn -> formatted_metrics(device, key, time_frame) end)
    end)
  end

  # Builds the charts out of the report that has just arrived, rather than
  # reading the history back for them.
  #
  # Two reasons, and either alone would be enough. The write is buffered, so a
  # read this soon comes back empty and the chart would say there was nothing
  # for the period -- of the reading the user just watched arrive. And there is
  # nothing to read anyway: no charts means the latest set was empty when the
  # page loaded, which means the device had never reported.
  defp seed_charts(socket, latest_metrics) do
    x = DateTime.to_unix(latest_metrics["timestamp"], :millisecond)

    latest_metrics
    |> metrics_to_chart()
    |> Enum.reduce(socket, fn key, socket ->
      socket
      |> put_chart_data(key, AsyncResult.ok(chart_data(socket, key), [%{x: x, y: latest_metrics[key]}]))
      |> put_has_chart_data(key, true)
    end)
  end

  defp assign_metadata(%{assigns: %{device: device}} = socket) do
    metadata =
      if device.latest_connection, do: device.latest_connection.metadata || %{}, else: %{}

    assign(socket, :metadata, Map.drop(metadata, standard_keys(device)))
  end

  # Moves the charts along to the time frame's current bounds.
  defp push_time_frame(socket), do: push_event(socket, "update-time-frame", time_frame_bounds(socket))

  # The bounds the charts are sent with each update, as unix milliseconds.
  # None while they're zoomed, so they stay where the user put them until they
  # reset the zoom.
  defp time_frame_bounds(%{assigns: %{zoom: {_from, _until}}}), do: %{}

  defp time_frame_bounds(socket) do
    %{charts_from_timestamp: from, charts_until_timestamp: until, time_frame: time_frame} = socket.assigns

    %{
      from: DateTime.to_unix(from, :millisecond),
      until: DateTime.to_unix(until, :millisecond),
      unit: get_time_unit(time_frame)
    }
  end

  defp standard_keys(%{firmware_metadata: nil}), do: []

  defp standard_keys(%{firmware_metadata: firmware_metadata}),
    do: firmware_metadata |> Map.keys() |> Enum.map(&to_string/1)

  defp formatted_metrics(device, key, time_frame) do
    device
    |> Metrics.get_device_metrics_by_key(key, time_frame)
    |> Enum.map(fn metric ->
      %{x: DateTime.to_unix(metric.timestamp, :millisecond), y: metric.value}
    end)
  end

  defp metrics_to_chart(latest_metrics) do
    keys = Map.keys(latest_metrics)

    keys
    |> Enum.reject(fn key ->
      key == "timestamp" or String.downcase(key) in @no_chart_metrics or
        Map.get(@superseded_charts, key) in keys
    end)
    |> Enum.sort_by(fn key -> {Enum.find_index(@chart_order, &(&1 == key)) || length(@chart_order), key} end)
  end

  defp suggested_max(key) do
    cond do
      key == "cpu_temp" -> 100
      String.starts_with?(key, "load_") -> 1
      String.ends_with?(key, "_percent") or String.ends_with?(key, "_percentage") -> 100
      true -> nil
    end
  end

  # `tab_params/3` runs from a `:handle_params` hook, so it fires again every
  # time the user navigates back onto this tab. A tick left over from an earlier
  # visit that lands while the tab is open re-arms itself alongside the new one,
  # and from then on both chains run for the life of the LiveView. Hold the ref
  # so a stale tick can be cancelled -- which is also why `:tick_timer` is not
  # in `cleanup/0`; dropping it would lose the only handle we have on it.
  defp schedule_tick(socket) do
    _ = if ref = socket.assigns[:tick_timer], do: Process.cancel_timer(ref)

    if connected?(socket) do
      assign(socket, :tick_timer, Process.send_after(self(), :tick, @tick_interval))
    else
      assign(socket, :tick_timer, nil)
    end
  end

  defp get_time_unit({"hour", _}), do: "minute"
  defp get_time_unit({"day", 1}), do: "hour"
  defp get_time_unit({"day", _}), do: "day"

  # The thresholds the device's resolved profile holds for each regular
  # metric. The Now card marks them on its bars and the chart hook draws them
  # across the charts, with the area past the warning threshold tinted.
  defp threshold_specs(nil), do: %{}

  defp threshold_specs(profile) do
    for metric <- profile.metrics, !metric.built_in, into: %{} do
      {metric.key, %{operator: metric.operator, warning: metric.warning_threshold, alert: metric.alert_threshold}}
    end
  end

  defp custom_metrics(metrics) do
    Enum.reject(metrics, &(elem(&1, 0) in @manual_metrics))
  end

  # The Now card's readings in the design's order, each only when the device
  # reports it, then any other metric the device reports.
  defp tiles(metrics, labels) do
    well_known =
      Enum.reject(
        [cpu_tile(metrics), memory_tile(metrics), disk_tile(metrics), temperature_tile(metrics), load_tile(metrics)],
        &is_nil/1
      )

    others =
      for {key, value} <- Enum.sort(custom_metrics(metrics)), is_number(value) do
        %{
          id: key,
          label: MetricLabels.label(key, labels),
          detail: nil,
          value: Utils.nice_round(value),
          unit: nil,
          percent: nil,
          key: key,
          keys: [key]
        }
      end

    well_known ++ others
  end

  defp cpu_tile(%{"cpu_usage_percent" => percent}) when is_number(percent) do
    %{
      id: "cpu",
      label: "CPU",
      detail: nil,
      value: round(percent),
      unit: "%",
      percent: percent,
      key: "cpu_usage_percent",
      keys: ["cpu_usage_percent"]
    }
  end

  defp cpu_tile(_metrics), do: nil

  defp memory_tile(%{"mem_used_percent" => percent} = metrics) when is_number(percent) do
    %{
      id: "memory",
      label: "Memory",
      detail: memory_detail(metrics),
      value: round(percent),
      unit: "%",
      percent: percent,
      key: "mem_used_percent",
      keys: ["mem_used_percent", "mem_used_mb"]
    }
  end

  defp memory_tile(%{"mem_used_mb" => used} = metrics) when is_number(used) do
    %{
      id: "memory",
      label: "Memory",
      detail: is_number(metrics["mem_size_mb"]) && "of #{megabytes(metrics["mem_size_mb"])} MB",
      value: megabytes(used),
      unit: "MB",
      percent: nil,
      key: "mem_used_mb",
      keys: ["mem_used_mb"]
    }
  end

  defp memory_tile(_metrics), do: nil

  defp memory_detail(%{"mem_used_mb" => used, "mem_size_mb" => size}) when is_number(used) and is_number(size) do
    "#{megabytes(used)} of #{megabytes(size)} MB"
  end

  defp memory_detail(_metrics), do: nil

  defp disk_tile(%{"disk_used_percentage" => percent} = metrics) when is_number(percent) do
    %{
      id: "disk",
      label: "Disk",
      detail: disk_detail(metrics),
      value: round(percent),
      unit: "%",
      percent: percent,
      key: "disk_used_percentage",
      keys: ["disk_used_percentage"]
    }
  end

  defp disk_tile(_metrics), do: nil

  defp disk_detail(%{"disk_total_kb" => total, "disk_available_kb" => available})
       when is_number(total) and is_number(available) do
    "#{gigabytes(total - available)} of #{gigabytes(total)} GB"
  end

  defp disk_detail(_metrics), do: nil

  defp temperature_tile(%{"cpu_temp" => temperature}) when is_number(temperature) do
    %{
      id: "cpu-temperature",
      label: "CPU temperature",
      detail: nil,
      value: round(temperature),
      unit: "°C",
      percent: nil,
      key: "cpu_temp",
      keys: ["cpu_temp"]
    }
  end

  defp temperature_tile(_metrics), do: nil

  defp load_tile(metrics) do
    values = Map.take(metrics, @load_keys)

    if Enum.any?(values, fn {_key, value} -> is_number(value) end) do
      %{id: "load", kind: :load, label: "Load average", values: values, key: "load_15min", keys: @load_keys}
    end
  end

  defp megabytes(value), do: number_to_delimited(value, precision: 0)

  # Devices report disk sizes in KiB, as `df` does.
  defp gigabytes(kilobytes), do: Utils.format_number(Float.round(kilobytes / 1_048_576, 1))

  defp load_value(value) when is_number(value), do: Utils.format_number(Float.round(value / 1, 2))
  defp load_value(_not_reported), do: "—"

  # A chart's current value: load averages to two places, as the Now card
  # shows them, anything else to one.
  defp reading("load_" <> _window, value), do: load_value(value)
  defp reading(_key, value), do: Utils.nice_round(value)

  defp clamp_percent(percent), do: percent |> max(0) |> min(100)

  # Where the thresholds fall along a percentage bar. One outside 0-100 has
  # nowhere to go.
  defp bar_ticks(nil), do: []

  defp bar_ticks(spec) do
    for {level, threshold} <- [warning: spec.warning, alert: spec.alert],
        is_number(threshold),
        threshold >= 0,
        threshold <= 100 do
      {level, threshold}
    end
  end

  defp level_text({"unhealthy", _key, _reason}), do: "text-alert-content"
  defp level_text(_warning), do: "text-warning-content"

  defp level_track(:alert), do: "bg-alert/22"
  defp level_track(:warning), do: "bg-warning/22"
  defp level_track(_within), do: "bg-line-default"

  defp level_fill(:alert), do: "bg-alert"
  defp level_fill(:warning), do: "bg-warning"
  defp level_fill(_within), do: "bg-content-faint"

  # Why a metric engaged, as the profile judged it: "≥ 85% for 62% of the
  # last hour" for a share of the window, "≥ 85% over the last hour" for the
  # median over it.
  defp breach_text(%{"aggregation" => "share"} = reason, unit) do
    "#{operator_symbol(reason["operator"])} #{with_unit(Utils.format_number(reason["threshold"]), unit)} for #{reason["value"]}% of #{last_period(reason["period_seconds"])}"
  end

  defp breach_text(%{"aggregation" => "count"} = reason, _unit) do
    "#{Utils.format_number(reason["value"])} in #{last_period(reason["period_seconds"])}, threshold #{Utils.format_number(reason["threshold"])}"
  end

  defp breach_text(%{"period_seconds" => seconds} = reason, unit) when is_integer(seconds) do
    "#{operator_symbol(reason["operator"])} #{with_unit(Utils.format_number(reason["threshold"]), unit)} over #{last_period(seconds)}"
  end

  defp breach_text(reason, unit) do
    "#{operator_symbol(reason["operator"])} #{with_unit(Utils.format_number(reason["threshold"]), unit)}"
  end

  defp operator_symbol(operator) when operator in [:lte, "lte"], do: "≤"
  defp operator_symbol(_gte), do: "≥"

  defp last_period(3600), do: "the last hour"
  defp last_period(86_400), do: "the last day"

  defp last_period(seconds) when is_integer(seconds) and rem(seconds, 3600) == 0,
    do: "the last #{div(seconds, 3600)} hours"

  defp last_period(seconds) when is_integer(seconds) and rem(seconds, 60) == 0,
    do: "the last #{div(seconds, 60)} minutes"

  defp last_period(seconds) when is_integer(seconds), do: "the last #{seconds} seconds"
  defp last_period(_unknown), do: "the period"

  defp thresholds_text(spec, unit) do
    operator = if spec.operator == :lte, do: "≤ ", else: ""

    "Warning #{operator}#{with_unit(Utils.format_number(spec.warning), unit)} · Alert #{operator}#{with_unit(Utils.format_number(spec.alert), unit)}"
  end

  # "88%", but "46 °C" and "1,612 MB".
  defp with_unit(value, nil), do: "#{value}"
  defp with_unit(value, "%"), do: "#{value}%"
  defp with_unit(value, unit), do: "#{value} #{unit}"

  defp breach_level(value, %{} = spec) when is_number(value) do
    breaches? = fn threshold ->
      is_number(threshold) and if(spec.operator == :lte, do: value <= threshold, else: value >= threshold)
    end

    cond do
      breaches?.(spec.alert) -> :alert
      breaches?.(spec.warning) -> :warning
      true -> nil
    end
  end

  defp breach_level(_value, _spec), do: nil

  defp breach_label(level, spec) do
    side = if spec.operator == :lte, do: "Below", else: "Above"
    "#{side} #{level}"
  end

  # A chart with a fixed scale, such as load average's 0 to 1, doesn't stretch
  # to thresholds far above it, so their lines aren't drawn. Said instead,
  # unless the readings have stretched the scale up to them.
  defp above_scale?(key, value, %{operator: :gte, warning: warning}) when is_number(value) and is_number(warning) do
    case suggested_max(key) do
      nil -> false
      max -> warning > max and value < max
    end
  end

  defp above_scale?(_key, _value, _spec), do: false

  defp chart_title(key, custom_labels) do
    case custom_labels do
      %{^key => label} -> label
      _no_custom_label -> chart_default_title(key) || MetricLabels.label(key, custom_labels)
    end
  end

  defp chart_default_title(key) do
    case Map.get(@chart_titles, key) do
      {title, _qualifier} -> title
      nil -> nil
    end
  end

  defp chart_qualifier(key) do
    case Map.get(@chart_titles, key) do
      {_title, qualifier} -> qualifier
      nil -> nil
    end
  end

  defp well_known?(key), do: Map.has_key?(@chart_titles, key)

  # A metric the device named itself shows its key beside the label it was
  # given, so the label can be matched back to what the device sends.
  defp show_key?(key, custom_labels), do: !well_known?(key) and chart_title(key, custom_labels) != key

  defp value_unit(key) do
    cond do
      key == "cpu_temp" -> "°C"
      String.ends_with?(key, "_percent") or String.ends_with?(key, "_percentage") -> "%"
      String.ends_with?(key, "_mb") -> "MB"
      true -> nil
    end
  end

  defp time_frame_label(unit, 1), do: "1 #{unit}"
  defp time_frame_label(unit, amount), do: "#{amount} #{unit}s"

  # "Nov 6, 11:15 AM – 2:15 PM PST", naming the day again only when the range
  # crosses one.
  defp time_range(from, until, time_zone) do
    until_format =
      if DateTimes.day_key(from, time_zone) == DateTimes.day_key(until, time_zone), do: :time, else: :short_datetime

    "#{DateTimes.to_local_string(from, time_zone, :short_datetime, false)} – #{DateTimes.to_local_string(until, time_zone, until_format)}"
  end

  # The profile's name as the health profiles page lists it.
  defp profile_name(%{platform: nil}), do: "Default profile"
  defp profile_name(%{platform: platform}), do: "#{platform} profile"

  defp health_docs(), do: "https://github.com/nerves-hub/nerves_hub_link?tab=readme-ov-file#configure-health"

  # Alarms reach the platform through either extension.
  defp alarms_reported?(product, device) do
    Enum.any?([:health, :alarms], &(product.extensions[&1] and device.extensions[&1]))
  end

  defp disconnected?(connection), do: is_nil(connection) || connection.status != :connected

  # Charts are keyed by metric name, and metric names come from the device --
  # `Extensions.Health` stores whatever keys a report carries. Deriving an
  # assign key per metric meant `String.to_atom/1` on device-controlled input,
  # and atoms are never reclaimed, so a fleet reporting novel keys made every
  # node that rendered this tab permanently heavier. A map keyed by the string
  # mints nothing.
  defp chart_data(socket, key), do: Map.get(socket.assigns.chart_data, key, AsyncResult.loading())

  defp put_chart_data(socket, key, result) do
    assign(socket, :chart_data, Map.put(socket.assigns.chart_data, key, result))
  end

  defp put_has_chart_data(socket, key, has_data?) do
    assign(socket, :has_chart_data, Map.put(socket.assigns.has_chart_data, key, has_data?))
  end

  defp validate_time_unit(unit) when unit in ~w(hour day minute second), do: unit
  defp validate_time_unit(_unit), do: elem(@default_time_frame, 0)
end
