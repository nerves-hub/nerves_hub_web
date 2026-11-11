defmodule NervesHubWeb.Components.DevicePage.LogsTab do
  @moduledoc """
  A device's log lines, newest first.

  New lines are streamed in as the device sends them, and the toggle at the top
  pauses that, because the moment you want to read a line closely is the moment
  it scrolls away. Resuming refetches, so nothing sent while paused is missed.

  ## Narrowing

  Lines can be searched and narrowed by level and by how far back to look. The
  filters live in the URL so a particular view of a device's logs can be linked
  to. A line streamed in while a filter is set has to pass it, by the same rules
  as the query (`NervesHub.Devices.LogLines.matches?/2`), so a line is on screen
  live exactly when it would be after a refresh.

  The level filter is a threshold, "warning and above" rather than a pick list.
  A device may log at any level it likes, so a line at a level this does not know
  is only found under "All levels".

  ## Going back

  The first page is the newest lines. Scrolling to the bottom asks for the next
  page of older ones, from the oldest line already shown, until the list reaches
  the most the tab will hold. That is a limit on the page, not on the data: a
  device may send five lines a second and this tab may be left open for hours,
  so something has to give. Past it the tab says so and points at the filters.

  The limit is also what keeps the live stream and the paging from disagreeing.
  Once the list is full each new line pushes the oldest one out, and paging is
  already switched off by then, so the line that fell off is never one a later
  page would have skipped over.
  """

  use NervesHubWeb, tab_component: :logs

  alias NervesHub.Devices.LogLines
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.DevicePage.TabNotice
  alias NervesHubWeb.Helpers.Timezone
  alias Phoenix.LiveView.JS

  @page_size 50
  @max_lines 1_000
  @max_search_length 200

  @unfiltered %{search: "", level: "all", range: "all"}

  # Each level is every level at or above it. `warn` is what Elixir's Logger
  # called `warning` before it settled on the syslog names, and older devices
  # still send it.
  @level_thresholds %{
    "error" => ~w(emergency alert critical error),
    "warning" => ~w(emergency alert critical error warning warn),
    "info" => ~w(emergency alert critical error warning warn notice info)
  }

  @level_options [
    {"All levels", "all"},
    {"Info and above", "info"},
    {"Warning and above", "warning"},
    {"Error and above", "error"}
  ]

  # Log lines are only kept for three days, so "any time" reaches back that far
  # and no further.
  @range_seconds %{
    "15m" => 15 * 60,
    "1h" => 60 * 60,
    "6h" => 6 * 60 * 60,
    "24h" => 24 * 60 * 60
  }

  @range_options [
    {"Any time", "all"},
    {"Last 15 minutes", "15m"},
    {"Last hour", "1h"},
    {"Last 6 hours", "6h"},
    {"Last 24 hours", "24h"}
  ]

  def tab_params(params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> assign(:streaming_enabled, streaming?(socket))
      |> assign(:log_filters, filters_from(params))
      |> configure_stream()
      |> fetch_logs()
      |> cont()
    else
      socket
      |> assign(:analytics_enabled, false)
      |> assign(:streaming_enabled, false)
      |> cont()
    end
  end

  # `:analytics_enabled` and `:streaming_enabled` are deliberately absent: the
  # Data History and Errors tabs set them too, and an inactive tab that cleans a
  # key another tab sets deletes it out from under whichever of them is active.
  # See `NervesHubWeb.Components.DevicePage.TabCleanupTest`.
  def cleanup() do
    [:has_logs, :log_inserted, :log_filters, :log_count, :log_cursor, :more_logs]
  end

  # Changing a filter patches the URL, which comes back through here. Someone who
  # paused streaming to read something should still be paused after narrowing
  # what they are reading, so the choice is only reset on arriving at the tab.
  # Arriving is told by the filters not being assigned: `cleanup/0` drops them
  # whenever another tab is the one showing.
  defp streaming?(%{assigns: %{log_filters: _filters, streaming_enabled: streaming_enabled}}), do: streaming_enabled
  defp streaming?(_socket), do: true

  defp configure_stream(%{assigns: %{streams: %{log_lines: _}}} = socket) do
    socket
  end

  defp configure_stream(socket) do
    stream_configure(socket, :log_lines,
      dom_id: fn log_line ->
        timestamp =
          log_line.timestamp
          |> DateTime.to_string()
          |> String.replace(" ", "-")
          |> String.replace(":", "-")
          |> String.replace(".", "-")

        "log-line-#{timestamp}"
      end
    )
  end

  defp filters_from(params) do
    %{
      search: params |> text_param("search") |> String.trim() |> String.slice(0, @max_search_length),
      level: choice(text_param(params, "level"), Map.keys(@level_thresholds)),
      range: choice(text_param(params, "range"), Map.keys(@range_seconds))
    }
  end

  defp text_param(params, key) do
    case params[key] do
      value when is_binary(value) -> if String.valid?(value), do: value, else: ""
      _other -> ""
    end
  end

  # An unrecognised choice shows everything rather than nothing. A hand-edited
  # or stale URL should not look like a device that has logged nothing.
  defp choice(value, allowed), do: if(value in allowed, do: value, else: "all")

  defp query_opts(filters, extra \\ []) do
    Keyword.merge(
      [levels: @level_thresholds[filters.level], search: filters.search, since: since(filters.range)],
      extra
    )
  end

  defp since(range) do
    case @range_seconds[range] do
      nil -> nil
      seconds -> DateTime.add(DateTime.utc_now(), -seconds)
    end
  end

  # Asks for one more line than a page holds. If it comes back there is
  # something older to show, and if it does not the list is complete, so the
  # tab never offers a "Show more" that turns out to have nothing behind it.
  defp read_page(socket, size, extra_opts) do
    opts = query_opts(socket.assigns.log_filters, [limit: size + 1] ++ extra_opts)
    {page, older} = socket.assigns.device |> LogLines.for_device(opts) |> Enum.split(size)

    {page, older != []}
  end

  defp fetch_logs(socket) do
    {page, more?} = read_page(socket, @page_size, [])

    socket
    |> stream(:log_lines, page, reset: true)
    |> assign(:has_logs, page != [])
    |> assign(:log_count, length(page))
    |> assign(:log_cursor, oldest_timestamp(page, nil))
    |> assign(:more_logs, more?)
    |> assign(:log_inserted, false)
  end

  # Lines older than the oldest one on screen. The cursor is exclusive, so two
  # lines logged in the same microsecond that straddle a page boundary lose the
  # second one. The API pages the same way and has the same edge.
  defp load_older(%{assigns: %{more_logs: true, log_cursor: %DateTime{} = cursor, log_count: count}} = socket)
       when count < @max_lines do
    size = min(@page_size, @max_lines - count)
    {page, more?} = read_page(socket, size, before: cursor)

    socket
    |> stream(:log_lines, page, at: -1)
    |> assign(:log_count, count + length(page))
    |> assign(:log_cursor, oldest_timestamp(page, cursor))
    |> assign(:more_logs, more?)
    |> assign(:log_inserted, false)
  end

  defp load_older(socket), do: socket

  defp oldest_timestamp([], fallback), do: fallback
  defp oldest_timestamp(page, _fallback), do: page |> List.last() |> Map.fetch!(:timestamp)

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("filter-logs", params, socket) do
    %{org: org, product: product, device: device} = socket.assigns

    socket
    |> push_patch(to: ~p"/org/#{org}/#{product}/devices/#{device}/logs?#{query_params(filters_from(params))}")
    |> halt()
  end

  def hooked_event("load-more-logs", _params, socket) do
    socket
    |> load_older()
    |> halt()
  end

  def hooked_event("toggle-log-streaming", _, %{assigns: %{streaming_enabled: false}} = socket) do
    socket
    |> assign(:streaming_enabled, true)
    |> fetch_logs()
    |> halt()
  end

  def hooked_event("toggle-log-streaming", _, %{assigns: %{streaming_enabled: true}} = socket) do
    socket
    |> assign(:streaming_enabled, false)
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  # Only what differs from showing everything, so an unfiltered tab keeps its
  # plain URL.
  defp query_params(filters) do
    filters
    |> Map.reject(fn {key, value} -> value == @unfiltered[key] end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  def hooked_info(
        %Broadcast{event: "logs:received", payload: log_line},
        %{assigns: %{streaming_enabled: true}} = socket
      ) do
    if LogLines.matches?(log_line, query_opts(socket.assigns.log_filters)) do
      socket
      |> insert_live(log_line)
      |> halt()
    else
      halt(socket)
    end
  end

  def hooked_info(%Broadcast{event: "logs:received"}, %{assigns: %{streaming_enabled: false}} = socket) do
    halt(socket)
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  # Once the list is full the oldest line is pushed out to make room, so there
  # is history behind what is on screen whether or not there was before.
  defp insert_live(socket, log_line) do
    %{log_count: count, more_logs: more_logs} = socket.assigns

    socket
    |> stream_insert(:log_lines, log_line, at: 0, limit: @max_lines)
    |> assign(:log_count, min(count + 1, @max_lines))
    |> assign(:more_logs, more_logs or count >= @max_lines)
    |> assign(:has_logs, true)
    |> assign(:log_inserted, true)
  end

  def render(%{analytics_enabled: false} = assigns) do
    ~H"""
    <TabNotice.render title="Analytics aren't enabled for your platform." detail="Check with your Ops team for more information." />
    """
  end

  def render(%{product: %{extensions: %{logging: false}}} = assigns) do
    ~H"""
    <TabNotice.render title="Device logs aren't enabled for this product." detail="Please check the product settings." />
    """
  end

  def render(%{device: %{extensions: %{logging: false}}} = assigns) do
    ~H"""
    <TabNotice.render title="Device logs aren't enabled." detail="Please check the device settings." />
    """
  end

  # Nothing received at all, as opposed to nothing that matches: there is
  # nothing to search or narrow yet, so none of the controls are shown.
  def render(%{has_logs: false, log_filters: filters} = assigns) when filters == @unfiltered do
    ~H"""
    <div id="logs-tab" phx-mounted={JS.remove_class("opacity-0")} class="tab-content w-full opacity-0 transition-all duration-500">
      <TabNotice.render title="No logs have been received yet." detail="Lines appear here as the device sends them." />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="logs-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content w-full p-4 opacity-0 transition-all duration-500 sm:p-6 phx-click-loading:opacity-50"
    >
      <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <div class="flex min-h-14 shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-line-subtle px-4 py-2.5">
          <div class="flex flex-wrap items-center gap-2">
            <span
              :if={@streaming_enabled}
              class="flex h-7 items-center gap-1.5 rounded bg-success-soft pr-2.5 pl-2 text-xs font-medium text-success-content"
            >
              <span class="size-1.5 rounded-full bg-success"></span>Live
            </span>
            <span
              :if={!@streaming_enabled}
              class="flex h-7 items-center gap-1.5 rounded border border-line-default pr-2.5 pl-2 text-xs font-medium text-content-muted"
            >
              <span class="size-1.5 rounded-full bg-status-offline"></span>Paused
            </span>
            <.button id="toggle-log-streaming" size="sm" phx-click="toggle-log-streaming" aria-pressed={to_string(!@streaming_enabled)}>
              <span class={[if(@streaming_enabled, do: "lucide-pause", else: "lucide-play"), "size-3.5 text-content-muted"]} aria-hidden="true"></span>
              {if @streaming_enabled, do: "Pause", else: "Resume"}
            </.button>

            <span class="mx-0.5 hidden h-5 w-px bg-line-default sm:block" aria-hidden="true"></span>

            <form id="log-filters" phx-change="filter-logs" phx-submit="filter-logs" class="flex flex-wrap items-center gap-2">
              <label class="relative flex w-full items-center sm:w-70">
                <span class="pointer-events-none absolute left-2.5 lucide-search size-3.5 text-content-faint" aria-hidden="true"></span>
                <input
                  id="log-search"
                  type="search"
                  name="search"
                  value={@log_filters.search}
                  placeholder="Search messages"
                  aria-label="Search log messages"
                  maxlength={max_search_length()}
                  autocomplete="off"
                  phx-debounce="300"
                  class="h-7.5 w-full rounded border border-line-control border-b-line-strong bg-surface-raised py-0 pr-2.5 pl-8 text-ui text-content-body placeholder:text-content-faint focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
                />
              </label>
              <.filter_select name="level" label="Level" options={level_options()} value={@log_filters.level} />
              <.filter_select name="range" label="Time" options={range_options()} value={@log_filters.range} />
            </form>
          </div>
          <span :if={@has_logs} class="text-xs text-content-faint">Newest first · {@log_count} lines</span>
        </div>

        <div :if={!@has_logs} class="flex flex-col items-center justify-center gap-1 p-14 text-center">
          <span class="text-ui text-content-faint">No log lines match these filters.</span>
          <.link
            id="clear-log-filters"
            patch={~p"/org/#{@org}/#{@product}/devices/#{@device}/logs"}
            class="text-xs font-medium text-content-body underline decoration-line-strong underline-offset-4 hover:decoration-content-muted"
          >
            Clear filters
          </.link>
        </div>

        <%!-- The list itself is the stream container, so the "Show older
              lines" control cannot be inside it (new lines are appended after
              whatever else is in there). This scrolls sideways, and holds both. --%>
        <div :if={@has_logs} class="overflow-x-auto p-2">
          <div id="log_lines" phx-update="stream" phx-hook="LogDayStarts" class="flex min-w-fit flex-col gap-px">
            <div
              :for={{dom_id, line} <- @streams.log_lines}
              id={dom_id}
              data-day={local_date(line.timestamp, @time_zone)}
              phx-mounted={@log_inserted && fade_in()}
              class="group/line flex flex-col gap-px"
            >
              <%!-- Shown above the first line of each day; see the
                    LogDayStarts hook. --%>
              <div class="hidden h-7 shrink-0 items-center gap-2.5 px-2 group-data-day-start/line:flex">
                <span class="text-label font-medium whitespace-nowrap text-content-faint uppercase">
                  {day_heading(line.timestamp, @time_zone)}
                </span>
                <span class="h-px grow bg-line-subtle"></span>
              </div>
              <div class={["flex items-start gap-4 rounded-[3px] px-2 py-0.75 font-mono text-xs/4.5", alert_level?(line.level) && "bg-alert-soft"]}>
                <.local_datetime at={line.timestamp} time_zone={@time_zone} format={:log_time} zone_label={false} class="w-23 shrink-0 text-content-faint" />
                <div data-log-level={line.level} class={["w-14 shrink-0", level_class(line.level)]}>{line.level}</div>
                <div class={["pr-4 whitespace-pre", if(alert_level?(line.level), do: "text-content-strong", else: "text-content-body")]}>{line.message}</div>
              </div>
            </div>
          </div>

          <div class="flex flex-wrap items-center justify-center gap-3 pt-4 pb-2">
            <%!-- `data-count` changes with every page, which is what makes the
                  hook see an update and check whether this is still on screen. --%>
            <.button
              :if={@more_logs and @log_count < max_lines()}
              id="show-more-logs"
              size="sm"
              phx-hook="LoadMoreOnVisible"
              data-event="load-more-logs"
              data-list="log_lines"
              data-count={@log_count}
              class="data-loading:opacity-50"
            >
              Show older lines
            </.button>
            <span :if={@more_logs and @log_count >= max_lines()} id="log-limit-reached" class="text-xs text-content-muted">
              Showing the newest {max_lines()} lines. Search, or narrow the time, to look further back.
            </span>
            <span class="text-xs text-content-faint">Lines are kept for 3 days</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:options, :list, required: true)
  attr(:value, :string, required: true)

  defp filter_select(assigns) do
    ~H"""
    <span class="grid grid-cols-1">
      <select
        name={@name}
        aria-label={@label}
        class="col-start-1 row-start-1 h-7.5 cursor-pointer appearance-none rounded border border-line-control border-b-line-strong bg-surface-raised bg-none py-0 pr-7 pl-2.5 text-ui text-content-body focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
      >
        <option :for={{label, value} <- @options} value={value} selected={value == @value}>{label}</option>
      </select>
      <span class="pointer-events-none col-start-1 row-start-1 mr-2 lucide-chevron-down size-3.5 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
    </span>
    """
  end

  @alert_levels ~w(emergency alert critical error)

  defp alert_level?(level), do: level in @alert_levels

  defp level_class(level) when level in @alert_levels, do: "text-alert-content"
  defp level_class(level) when level in ~w(warning warn), do: "text-warning-content"
  defp level_class("debug"), do: "text-content-faint"
  defp level_class(_level), do: "text-content-muted"

  # The day a line was logged in the viewer's zone, which the LogDayStarts hook
  # compares between neighbouring lines.
  defp local_date(timestamp, time_zone) do
    timestamp |> DateTime.shift_zone!(Timezone.resolve(time_zone)) |> DateTime.to_date() |> Date.to_iso8601()
  end

  # "Today · Nov 6", or just the date for an older day.
  defp day_heading(timestamp, time_zone) do
    case DateTimes.day_label(timestamp, time_zone) do
      relative when relative in ["Today", "Yesterday"] ->
        date = DateTime.shift_zone!(timestamp, Timezone.resolve(time_zone))
        "#{relative} · #{Calendar.strftime(date, "%b %-d")}"

      date ->
        date
    end
  end

  defp level_options(), do: @level_options
  defp range_options(), do: @range_options
  defp max_lines(), do: @max_lines
  defp max_search_length(), do: @max_search_length

  defp fade_in() do
    JS.transition(
      {"first:ease-in duration-500", "first:opacity-0 first:p-0 first:h-0", "first:opacity-100"},
      time: 3000,
      blocking: false
    )
  end
end
