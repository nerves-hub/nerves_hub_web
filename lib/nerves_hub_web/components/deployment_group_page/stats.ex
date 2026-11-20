defmodule NervesHubWeb.Components.DeploymentGroupPage.Stats do
  @moduledoc """
  A deployment group's Stats tab: how its releases went.

  It opens on the current release, and a select switches to another release or
  to all of them, held in the URL as `?release=` (a release number, or `all`).

  Downloads come from PostgreSQL and are read as the selection changes. How
  attempts ended, and how long they took, come from the update history in
  ClickHouse, read in a task so a slow ClickHouse never holds the page up; until
  it answers, or if it doesn't, those numbers show as a dash.
  `NervesHub.ManagedDeployments.ReleaseStats` holds the queries and explains the
  windows each release is counted over.

  The page re-renders every few seconds, and none of that reloads anything:
  only a different selection, or a new release, does.
  """

  use NervesHubWeb, :live_component

  import NervesHubWeb.Components.Fleet, only: [count_noun: 3, delimited: 1]

  alias NervesHub.ManagedDeployments
  alias NervesHub.ManagedDeployments.ReleaseStats
  alias NervesHubWeb.Components.DateTimes

  @duration_labels ["< 2m", "2–4m", "4–6m", "6–8m", "8–10m", "10–15m", "15–30m", "30m +"]

  @bucket_names %{
    3600 => "Hourly buckets",
    7200 => "Two-hour buckets",
    10_800 => "Three-hour buckets",
    21_600 => "Six-hour buckets",
    43_200 => "12-hour buckets",
    86_400 => "Daily buckets",
    172_800 => "Two-day buckets",
    604_800 => "Weekly buckets",
    1_209_600 => "Two-week buckets",
    2_592_000 => "30-day buckets"
  }

  # How many versions devices came from are listed before the rest are rolled
  # into one row.
  @source_rows 4

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    group = assigns.deployment_group
    key = {assigns.selection, group.releases_count, group.current_deployment_release_id}

    socket = assign(socket, assigns)

    if socket.assigns[:loaded] == key do
      ok(socket)
    else
      socket
      |> assign(:loaded, key)
      |> load()
      |> ok()
    end
  end

  defp load(socket) do
    %{deployment_group: group, selection: selection} = socket.assigns

    windows = group |> ManagedDeployments.list_deployment_releases() |> ReleaseStats.windows()
    selected = select(windows, selection, group.current_deployment_release_id)

    socket
    |> assign(:windows, windows)
    |> assign(:selected, selected)
    |> assign(:now, DateTime.utc_now())
    |> assign(:downloads, ReleaseStats.downloads_by_release(group))
    |> load_selected(selected)
  end

  defp select([], _selection, _current_id), do: nil
  defp select(_windows, "all", _current_id), do: :all

  defp select(windows, selection, current_id) do
    with number when is_binary(number) <- selection,
         {number, ""} <- Integer.parse(number),
         %{} = window <- Enum.find(windows, &(&1.release.number == number)) do
      window
    else
      _ -> Enum.find(windows, hd(windows), &(&1.release.id == current_id))
    end
  end

  defp load_selected(socket, nil), do: assign(socket, :history, :none)

  defp load_selected(socket, :all) do
    %{deployment_group: group, windows: windows} = socket.assigns

    start_history(socket, fn ->
      Map.put(ReleaseStats.outcomes_by_release(group, windows), :began, ReleaseStats.history_began(group))
    end)
  end

  defp load_selected(socket, window) do
    %{deployment_group: group, now: now} = socket.assigns

    sources = ReleaseStats.downloads_by_source(group, window)
    delta_sources = for %{delta?: true, source_uuid: uuid} <- sources, uuid, do: uuid

    socket
    |> assign(:sources, sources)
    |> assign(:deltas, ReleaseStats.deltas(window.release))
    |> assign(:steps, ReleaseStats.started_steps(window.release))
    |> start_history(fn ->
      detail = ReleaseStats.release_detail(group, window, delta_sources, now)
      uuids = detail.sources |> Enum.map(& &1.uuid) |> Enum.reject(&(&1 == ""))

      detail
      |> Map.put(:began, ReleaseStats.history_began(group))
      |> Map.put(:versions, ReleaseStats.versions(group, uuids))
    end)
  end

  # The selection travels with the result, so an answer for a release the
  # viewer has since left is dropped.
  defp start_history(socket, fun) do
    if ReleaseStats.analytics_enabled?() do
      key = socket.assigns.loaded

      socket
      |> assign(:history, :loading)
      |> start_async(:history, fn -> {key, fun.()} end)
    else
      assign(socket, :history, :disabled)
    end
  end

  @impl Phoenix.LiveComponent
  def handle_async(:history, {:ok, {key, result}}, socket) do
    if key == socket.assigns.loaded do
      noreply(assign(socket, :history, {:ok, result}))
    else
      noreply(socket)
    end
  end

  def handle_async(:history, {:exit, _reason}, socket), do: noreply(assign(socket, :history, :failed))

  @impl Phoenix.LiveComponent
  @decorate requires_membership()
  def handle_event("select-release", %{"release" => release}, socket) do
    noreply(push_patch(socket, to: "#{socket.assigns.path}?#{URI.encode_query(release: release)}"))
  end

  @impl Phoenix.LiveComponent
  def render(%{selected: nil} = assigns) do
    ~H"""
    <div id="deployment-group-stats" class="p-4 sm:p-6">
      <div class="flex flex-col items-center gap-3 rounded-card border border-dashed border-line-dashed px-6 py-12 text-center">
        <span class="flex size-10 items-center justify-center rounded-full bg-surface-muted" aria-hidden="true">
          <span class="lucide-chart-column size-5 text-content-faint"></span>
        </span>
        <p class="text-ui text-content-muted">Stats appear here once the group has a release.</p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    # Built once here, since both the note above the table and the table itself
    # need them.
    rows =
      if assigns.selected == :all do
        %{windows: windows, downloads: downloads, history: history, deployment_group: group, time_zone: zone} = assigns
        release_rows(windows, downloads, history, group, zone)
      else
        []
      end

    assigns = assign(assigns, rows: rows, dashed?: Enum.any?(rows, & &1.dashed?))

    ~H"""
    <div id="deployment-group-stats" class="@container flex flex-col gap-4 p-4 sm:gap-5 sm:p-6">
      <div class="flex flex-col gap-x-4 gap-y-2 @3xl:flex-row @3xl:items-center">
        <form id="stats-release-form" phx-change="select-release" phx-target={@myself} class="shrink-0 @3xl:w-62">
          <label for="stats-release" class="sr-only">Release</label>
          <%!-- The select is laid over the face, unseen, so the face can set the
               version in mono and picking still opens the browser's own menu. --%>
          <div class="relative flex h-8 items-center gap-2 rounded border border-line-control border-b-line-strong bg-surface-raised pr-2 pl-2.5 focus-within:border-primary focus-within:ring-3 focus-within:ring-primary/20 max-sm:h-10 max-sm:rounded-md">
            <span class="grow truncate text-ui/4 text-content-muted max-sm:text-sm" aria-hidden="true">
              <%= if @selected == :all do %>
                <span class="text-content-strong">All releases</span>
              <% else %>
                <span class="font-mono font-medium text-content-strong">{@selected.release.firmware.version}</span>
                Release {@selected.release.number}{if @selected.release.id == @deployment_group.current_deployment_release_id, do: " · current"}
              <% end %>
            </span>
            <span class="lucide-chevron-down--bold size-3.5 text-content-faint" aria-hidden="true"></span>
            <select id="stats-release" name="release" class="absolute inset-0 size-full cursor-pointer appearance-none opacity-0">
              <option value="all" selected={@selected == :all}>All releases</option>
              <option :for={window <- @windows} value={window.release.number} selected={@selected != :all and @selected.release.id == window.release.id}>
                {release_label(window, @deployment_group)}
              </option>
            </select>
          </div>
        </form>
        <p id="stats-window" class="grow text-ui text-content-muted">{window_text(@selected, @windows, @now, @time_zone)}</p>
        <p class="text-xs text-content-muted @3xl:text-right">{note(@selected, @history, @time_zone, @dashed?)}</p>
      </div>

      <%= if @selected == :all do %>
        <.all_releases rows={@rows} history={@history} deployment_group={@deployment_group} path={@path} time_zone={@time_zone} />
      <% else %>
        <.one_release
          window={@selected}
          downloads={Map.get(@downloads, @selected.release.id)}
          sources={@sources}
          deltas={@deltas}
          steps={@steps}
          history={@history}
          deployment_group={@deployment_group}
          now={@now}
          time_zone={@time_zone}
        />
      <% end %>
    </div>
    """
  end

  ## One release

  attr(:window, :map, required: true)
  attr(:downloads, :map, default: nil)
  attr(:sources, :list, required: true)
  attr(:deltas, :map, required: true)
  attr(:steps, :list, required: true)
  attr(:history, :any, required: true)
  attr(:deployment_group, :map, required: true)
  attr(:now, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp one_release(assigns) do
    assigns =
      assign(assigns,
        detail: detail(assigns.history),
        version: assigns.window.release.firmware.version,
        kept: kept(assigns.history, assigns.downloads)
      )

    ~H"""
    <.figures id="stats-figures">
      <.figure label="Succeeded" value={succeeded_value(@detail, @kept)}>
        <%= cond do %>
          <% is_nil(@detail) or !@kept.outcomes -> %>
            {missing(@history)}
          <% @detail.attempts.succeeded + @detail.attempts.failed == 0 -> %>
            No updates have ended yet.
          <% true -> %>
            <span class="font-mono">{delimited(@detail.attempts.succeeded)}</span>
            of <span class="font-mono">{delimited(@detail.attempts.succeeded + @detail.attempts.failed)}</span>
            attempts<span :if={@detail.attempts.rescheduled > 0}>
              · <span class="font-mono">{delimited(@detail.attempts.rescheduled)}</span> rescheduled left out
            </span>
        <% end %>
      </.figure>
      <.figure label="Failed attempts" value={if @detail && @kept.outcomes, do: delimited(@detail.attempts.failed), else: "—"}>
        <%= cond do %>
          <% is_nil(@detail) or !@kept.outcomes -> %>
            {missing(@history)}
          <% @detail.attempts.failed == 0 -> %>
            {if @window.to, do: "None.", else: "None so far."}
          <% true -> %>
            On <.counted count={@detail.failed_devices} one="device" many="devices" />. <span class="font-mono">{delimited(@detail.recovered_devices)}</span> got it on a later try.
        <% end %>
      </.figure>
      <.figure label="Typical update" value={if @detail && @kept.durations, do: duration(@detail.durations.median), else: "—"}>
        <%= cond do %>
          <% is_nil(@detail) or !@kept.durations -> %>
            {missing(@history)}
          <% is_nil(@detail.durations.median) -> %>
            No timed updates yet.
          <% true -> %>
            Median. 9 in 10 within <span class="font-mono">{duration(@detail.durations.p90)}</span>.
        <% end %>
      </.figure>
      <.figure label="Downloaded" value={bytes(@downloads && @downloads.downloaded)}>
        <%= if @downloads && @downloads.saved > 0 do %>
          Delta updates saved <span class="font-mono">{bytes(@downloads.saved)}</span>.
        <% else %>
          {if @downloads, do: "No delta updates.", else: "No devices have taken it yet."}
        <% end %>
      </.figure>
    </.figures>

    <.attempts_chart :if={@kept.outcomes} window={@window} detail={@detail} steps={@steps} history={@history} now={@now} time_zone={@time_zone} />

    <div class="grid gap-4 sm:gap-5 @5xl:grid-cols-[3fr_2fr]">
      <.durations_chart :if={@kept.durations} detail={@detail} history={@history} version={@version} />
      <.downloads_card downloads={@downloads} sources={@sources} detail={@detail} versions={versions(@history)} />
    </div>

    <%!-- The version table gets the wider column: at half the width its
          download notes wrap. --%>
    <div :if={@kept.outcomes} class="grid gap-4 sm:gap-5 @5xl:grid-cols-[2fr_3fr]">
      <.reasons_card detail={@detail} history={@history} />
      <.sources_card detail={@detail} history={@history} deltas={@deltas} deployment_group={@deployment_group} />
    </div>
    """
  end

  attr(:window, :map, required: true)
  attr(:detail, :map, required: true)
  attr(:steps, :list, required: true)
  attr(:history, :any, required: true)
  attr(:now, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp attempts_chart(assigns) do
    detail = assigns.detail

    assigns =
      assigns
      |> assign(:chart, detail && timeline(assigns.window, detail, assigns.steps, assigns.now))
      |> assign(:empty?, detail != nil and detail.attempts.succeeded + detail.attempts.failed == 0)

    ~H"""
    <section id="stats-attempts" aria-labelledby="stats-attempts-title" class="flex flex-col gap-3 rounded-card border border-line-default bg-surface-raised p-5 shadow-card max-sm:p-4">
      <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <div class="flex items-baseline gap-3">
          <h2 id="stats-attempts-title" class="text-group-title text-content-strong">Attempts over time</h2>
          <span :if={@detail && !@empty?} class="text-xs text-content-faint">{@chart.bucket_name}</span>
        </div>
        <div :if={@detail && !@empty?} class="flex items-center gap-4 text-xs text-content-body">
          <span class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs" style="background: var(--color-chart-3)"></span> Succeeded <span class="font-mono">{delimited(@detail.attempts.succeeded)}</span>
          </span>
          <span class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs" style="background: var(--color-chart-alert)"></span> Failed <span class="font-mono">{delimited(@detail.attempts.failed)}</span>
          </span>
        </div>
      </div>

      <%= cond do %>
        <% is_nil(@detail) -> %>
          <.pending history={@history} class="h-36" />
        <% @empty? -> %>
          <p id="stats-attempts-empty" class="flex h-36 items-center justify-center text-center text-ui text-content-muted">
            {if @window.to, do: "No update attempts ended before this release was replaced.", else: "No update attempts have ended yet."}
          </p>
        <% true -> %>
          <div class="relative pt-5">
            <span
              :for={step <- @chart.steps}
              class={[
                "absolute top-0 max-w-40 truncate text-xs",
                cond do
                  step.x < 0.1 -> "translate-x-0"
                  step.x > 0.9 -> "-translate-x-full"
                  true -> "-translate-x-1/2"
                end,
                if(step.stopped?, do: "text-alert-content", else: "text-content-muted")
              ]}
              style={"left: #{step.x * 100}%"}
              title={step.title}
              data-step
            >
              {step.label}{if step.stopped?, do: " · stopped on failures"}
            </span>
            <svg
              viewBox={"0 0 #{@chart.width} #{@chart.height}"}
              preserveAspectRatio="none"
              class="block h-36 w-full"
              role="img"
              aria-label={"#{@detail.attempts.succeeded} succeeded and #{@detail.attempts.failed} failed, in #{String.downcase(@chart.bucket_name)}"}
            >
              <g :for={bar <- @chart.bars}>
                <title>{bar.title}</title>
                <rect x={bar.x} y="0" width={bar.width} height={@chart.height} fill="transparent" />
                <rect :if={bar.ok > 0} x={bar.x + 1} y={@chart.baseline - 1 - bar.ok} width={max(bar.width - 2, 1)} height={bar.ok} rx="1" style="fill: var(--color-chart-3)" />
                <rect :if={bar.failed > 0} x={bar.x + 1} y={@chart.baseline + 1} width={max(bar.width - 2, 1)} height={bar.failed} rx="1" style="fill: var(--color-chart-alert)" />
              </g>
              <line x1="0" x2={@chart.width} y1={@chart.baseline} y2={@chart.baseline} vector-effect="non-scaling-stroke" style="stroke: var(--color-line-strong)" />
              <line
                :for={step <- @chart.steps}
                x1={step.x * @chart.width}
                x2={step.x * @chart.width}
                y1="0"
                y2={@chart.height}
                vector-effect="non-scaling-stroke"
                stroke-dasharray="3 3"
                style={"stroke: #{if step.stopped?, do: "var(--color-chart-alert)", else: "var(--color-line-strong)"}"}
              />
            </svg>
          </div>
          <div class="flex justify-between font-mono text-xs text-content-faint">
            <span>{DateTimes.to_local_string(@window.from, @time_zone, :short_datetime, false)}</span>
            <span>{if @window.to, do: DateTimes.to_local_string(@window.to, @time_zone, :short_datetime, false), else: "now"}</span>
          </div>
      <% end %>
    </section>
    """
  end

  attr(:detail, :map, required: true)
  attr(:history, :any, required: true)
  attr(:version, :string, required: true)

  defp durations_chart(assigns) do
    assigns = assign(assigns, :chart, assigns.detail && durations(assigns.detail.durations))

    ~H"""
    <section id="stats-durations" aria-labelledby="stats-durations-title" class="flex min-w-0 flex-col gap-4 rounded-card border border-line-default bg-surface-raised p-5 shadow-card max-sm:p-4">
      <div class="flex flex-wrap items-start justify-between gap-x-6 gap-y-2">
        <div class="flex flex-col gap-0.5">
          <h2 id="stats-durations-title" class="text-group-title text-content-strong">How long updates took</h2>
          <p class="text-xs text-content-muted">
            From sending the update to the device rejoining on <span class="font-mono">{@version}</span>. Successful updates only.
          </p>
        </div>
        <div :if={@detail} class="flex flex-col gap-1 text-xs text-content-body">
          <span :if={@detail.durations.delta_median} class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs" style="background: var(--color-chart-1)"></span> Delta · median <span class="font-mono">{duration(@detail.durations.delta_median)}</span>
          </span>
          <span :if={@detail.durations.full_median} class="flex items-center gap-1.5">
            <span class="size-2.5 rounded-xs" style="background: var(--color-chart-other)"></span> Full · median <span class="font-mono">{duration(@detail.durations.full_median)}</span>
          </span>
        </div>
      </div>

      <%= cond do %>
        <% is_nil(@detail) -> %>
          <.pending history={@history} class="h-44" />
        <% is_nil(@detail.durations.median) -> %>
          <p class="flex h-44 items-center justify-center text-ui text-content-muted">No timed updates yet.</p>
        <% true -> %>
          <div class="flex flex-col gap-2">
            <div class={["relative", if(@chart.stacked?, do: "h-44 pt-10", else: "h-40 pt-6")]}>
              <div :for={marker <- @chart.markers} class="absolute inset-y-0 w-0" style={"left: #{marker.x * 100}%"} data-marker>
                <span class={[
                  "absolute text-xs whitespace-nowrap text-content-body",
                  if(marker.row == 1, do: "top-4", else: "top-0"),
                  cond do
                    marker.x < 0.15 -> "left-0"
                    marker.x > 0.8 -> "right-0"
                    true -> "left-0 -translate-x-1/2"
                  end
                ]}>
                  {marker.label}
                </span>
                <span class={["absolute bottom-0 left-0 border-l border-dashed border-line-strong", if(marker.row == 1, do: "top-9", else: "top-5")]}></span>
              </div>
              <ol class="flex h-full items-end gap-1 border-b border-line-strong sm:gap-2" aria-label="Updates by how long they took">
                <li :for={column <- @chart.columns} class="flex h-full flex-1 flex-col justify-end" title={column.title}>
                  <span class="sr-only">{column.title}</span>
                  <span
                    :if={column.full > 0}
                    class="shrink-0 rounded-t-xs"
                    style={"height: #{stacked_height(column.full, column.delta > 0)}; background: var(--color-chart-other)"}
                  ></span>
                  <span
                    :if={column.delta > 0}
                    class={["shrink-0", column.full == 0 && "rounded-t-xs", column.full > 0 && "mt-0.5"]}
                    style={"height: #{stacked_height(column.delta, column.full > 0)}; background: var(--color-chart-1)"}
                  ></span>
                </li>
              </ol>
            </div>
            <ol class="flex gap-1 font-mono text-xs text-content-faint sm:gap-2" aria-hidden="true">
              <li :for={{range, unit} <- duration_ticks()} class="min-w-0 flex-1 text-center whitespace-nowrap">
                {range}<span class="max-sm:hidden">{unit}</span>
              </li>
            </ol>
          </div>
      <% end %>
    </section>
    """
  end

  # A bar's height in its column. When a column stacks full and delta bars,
  # each gives up a pixel for the 2px gap between them, so the stack still
  # ends at the top of the column instead of 2px past it.
  defp stacked_height(percent, false), do: "#{percent}%"
  defp stacked_height(percent, true), do: "max(1px, calc(#{percent}% - 1px))"

  attr(:downloads, :map, default: nil)
  attr(:sources, :list, required: true)
  attr(:detail, :map, required: true)
  attr(:versions, :map, required: true)

  defp downloads_card(assigns) do
    assigns = assign(assigns, :rows, download_rows(assigns.sources, assigns.versions))

    ~H"""
    <section id="stats-downloads" aria-labelledby="stats-downloads-title" class="flex min-w-0 flex-col gap-4 rounded-card border border-line-default bg-surface-raised p-5 shadow-card max-sm:p-4">
      <div class="flex flex-col gap-0.5">
        <h2 id="stats-downloads-title" class="text-group-title text-content-strong">Downloads</h2>
        <p :if={@downloads} class="text-xs text-content-muted">
          What the <span class="font-mono">{delimited(@downloads.updated)}</span> successful {if @downloads.updated == 1, do: "update", else: "updates"} downloaded.
        </p>
      </div>

      <p :if={!@downloads} id="stats-downloads-empty" class="flex h-36 items-center justify-center text-center text-ui text-content-muted">
        No devices have taken this release yet.
      </p>

      <div :if={@downloads} class="flex flex-col gap-4">
        <div class="flex flex-col gap-3">
          <div class="flex flex-col gap-1.5">
            <div class="flex justify-between text-ui">
              <span class="text-content-body">{if @downloads.saved > 0, do: "With delta updates", else: "Downloaded"}</span>
              <span class="font-mono text-content-strong">{bytes(@downloads.downloaded)}</span>
            </div>
            <div class="flex h-2 gap-0.5 overflow-clip rounded-xs">
              <span
                :for={row <- @rows}
                :if={row.downloaded > 0}
                style={"width: #{share(row.downloaded, @downloads.downloaded + @downloads.saved)}%; background: #{if row.delta?, do: "var(--color-chart-1)", else: "var(--color-chart-other)"}"}
              ></span>
            </div>
          </div>
          <div :if={@downloads.saved > 0} class="flex flex-col gap-1.5">
            <div class="flex justify-between text-ui">
              <span class="text-content-muted">If every device took the full firmware</span>
              <span class="font-mono text-content-muted">{bytes(@downloads.downloaded + @downloads.saved)}</span>
            </div>
            <div class="h-2 rounded-xs" style="background: color-mix(in oklab, var(--color-chart-other) 25%, transparent)"></div>
          </div>
        </div>

        <ul class="flex flex-col divide-y divide-line-subtle border-t border-line-subtle">
          <li :for={row <- @rows} class="flex items-center gap-3 py-2.5 text-ui">
            <span class="size-2.5 shrink-0 rounded-xs" style={"background: #{if row.delta?, do: "var(--color-chart-1)", else: "var(--color-chart-other)"}"}></span>
            <span class="grow text-content-body">
              <%= if row.delta? do %>
                Delta from <span class="font-mono">{row.label}</span>
              <% else %>
                Full firmware
              <% end %>
            </span>
            <span class="font-mono text-xs whitespace-nowrap text-content-muted max-sm:hidden">{delimited(row.updated)} × {bytes(div(row.downloaded, max(row.updated, 1)))}</span>
            <span class="w-16 text-right font-mono text-content-strong">{bytes(row.downloaded)}</span>
          </li>
        </ul>

        <p class="text-xs text-content-muted">
          Worked out from firmware and delta sizes. Failed and retried downloads aren’t counted.
        </p>
      </div>
    </section>
    """
  end

  # A count and its noun inside a sentence, with the count in mono like every
  # other number on the tab: "On 21 devices."
  attr(:count, :integer, required: true)
  attr(:one, :string, required: true)
  attr(:many, :string, required: true)

  defp counted(assigns) do
    ~H|<span class="font-mono">{delimited(@count)}</span> {if @count == 1, do: @one, else: @many}|
  end

  attr(:detail, :map, required: true)
  attr(:history, :any, required: true)

  defp reasons_card(assigns) do
    assigns = assign(assigns, :reasons, assigns.detail && reasons(assigns.detail))

    ~H"""
    <section id="stats-reasons" aria-labelledby="stats-reasons-title" class="flex min-w-0 flex-col rounded-card border border-line-default bg-surface-raised shadow-card">
      <div class="flex flex-col gap-0.5 px-5 pt-5 pb-3 max-sm:px-4">
        <h2 id="stats-reasons-title" class="text-group-title text-content-strong">Why updates failed</h2>
        <p :if={@detail && @detail.attempts.failed > 0} class="text-xs text-content-muted">
          <.counted count={@detail.attempts.failed} one="failed attempt" many="failed attempts" />, by how they ended and what the device said.
        </p>
      </div>
      <%= cond do %>
        <% is_nil(@detail) -> %>
          <.pending history={@history} class="h-40" />
        <% @detail.attempts.failed == 0 -> %>
          <p id="stats-reasons-empty" class="flex h-40 items-center justify-center px-5 pb-5 text-center text-ui text-content-muted max-sm:px-4">No updates have failed.</p>
        <% true -> %>
          <ul class="flex flex-col divide-y divide-line-subtle border-t border-line-subtle">
            <li :for={reason <- @reasons.shown} class="flex items-center gap-4 px-5 py-3 max-sm:px-4" data-reason>
              <div class="flex min-w-0 grow flex-col gap-0.5">
                <span class={["text-ui wrap-break-word text-content-strong", reason.reason && "font-mono"]}>
                  {reason.reason || silent_reason(reason.status)}
                </span>
                <span class="text-xs text-content-muted">{status_label(reason.status)}</span>
              </div>
              <span class="h-1 w-24 shrink-0 overflow-clip rounded-full bg-line-subtle max-sm:w-12">
                <span class="block h-full rounded-full" style={"width: #{share(reason.count, @reasons.max)}%; background: var(--color-chart-alert)"}></span>
              </span>
              <span class="w-8 shrink-0 text-right font-mono text-ui text-content-strong">{delimited(reason.count)}</span>
            </li>
            <li :if={@reasons.rest > 0} class="px-5 py-3 text-xs text-content-muted max-sm:px-4">
              And <.counted count={@reasons.rest} one="more attempt" many="more attempts" />, for <.counted count={@reasons.rest_reasons} one="other reason" many="other reasons" />.
            </li>
          </ul>
      <% end %>
    </section>
    """
  end

  attr(:detail, :map, required: true)
  attr(:history, :any, required: true)
  attr(:deltas, :map, required: true)
  attr(:deployment_group, :map, required: true)

  defp sources_card(assigns) do
    assigns =
      assign(assigns, :rows, assigns.detail && source_rows(assigns.detail, versions(assigns.history), assigns.deltas))

    ~H"""
    <section id="stats-sources" aria-labelledby="stats-sources-title" class="flex min-w-0 flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
      <div class="flex flex-col gap-0.5 px-5 pt-5 pb-3 max-sm:px-4">
        <h2 id="stats-sources-title" class="text-group-title text-content-strong">By the version devices came from</h2>
        <p :if={@detail && @rows != []} class="text-xs text-content-muted">Where a delta was missing or failed to build, devices took the full firmware.</p>
      </div>
      <%= cond do %>
        <% is_nil(@detail) -> %>
          <.pending history={@history} class="h-40" />
        <% @rows == [] -> %>
          <p id="stats-sources-empty" class="flex h-40 items-center justify-center px-5 pb-5 text-center text-ui text-content-muted max-sm:px-4">No updates have ended yet.</p>
        <% true -> %>
          <table class="w-full text-ui">
            <thead>
              <tr class="h-9 border-y border-line-default bg-surface-muted text-label text-content-faint uppercase">
                <th class="pl-5 text-left font-medium max-sm:pl-4">Came from</th>
                <th class="pl-3 text-left font-medium max-sm:hidden">Download</th>
                <th class="pl-3 text-right font-medium">Updated</th>
                <th class="pl-3 text-right font-medium">Succeeded</th>
                <th class="pr-5 pl-3 text-right font-medium max-sm:hidden">Median</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-line-subtle">
              <tr :for={row <- @rows} class="h-row" data-source>
                <td class="py-3 pl-5 max-sm:pl-4">
                  <span class={[row.version && "font-mono text-content-strong", !row.version && "text-content-body"]}>{row.label}</span>
                </td>
                <td class="py-3 pl-3 max-sm:hidden">
                  <span :if={row.download} class="flex items-center gap-1.5 text-content-body">
                    <span class="size-2.5 shrink-0 rounded-xs" style={"background: #{if row.download.delta?, do: "var(--color-chart-1)", else: "var(--color-chart-other)"}"}></span>
                    <span>
                      {if row.download.delta?, do: "Delta", else: "Full"}<span :if={row.download.note} class={row.download.alert? && "text-alert-content"}> · {row.download.note}</span>
                    </span>
                  </span>
                </td>
                <td class="py-3 pl-3 text-right font-mono text-content-strong">{delimited(row.succeeded)}</td>
                <td class="py-3 pl-3 text-right font-mono whitespace-nowrap text-content-body">
                  {percent(row.succeeded, row.succeeded + row.failed)}<span :if={row.failed > 0} class="text-xs text-content-muted"> · {delimited(row.failed)} failed</span>
                </td>
                <td class="py-3 pr-5 pl-3 text-right font-mono text-content-body max-sm:hidden">{duration(row.median)}</td>
              </tr>
            </tbody>
          </table>
      <% end %>
    </section>
    """
  end

  ## All releases

  attr(:rows, :list, required: true, doc: "from `release_rows/5`")
  attr(:history, :any, required: true)
  attr(:deployment_group, :map, required: true)
  attr(:path, :string, required: true)
  attr(:time_zone, :string, required: true)

  defp all_releases(assigns) do
    assigns = assign(assigns, :totals, totals(assigns.rows, assigns.history))

    ~H"""
    <.figures id="stats-figures">
      <.figure label="Succeeded" value={percent(@totals.succeeded, @totals.succeeded + @totals.failed)}>
        <%= cond do %>
          <% !@totals.kept? -> %>
            {missing(@history)}
          <% @totals.attempted_releases == [] -> %>
            No updates have ended yet.
          <% true -> %>
            <span class="font-mono">{delimited(@totals.succeeded)}</span>
            of <span class="font-mono">{delimited(@totals.succeeded + @totals.failed)}</span>
            attempts{release_range(@totals.attempted_releases, @rows)}
        <% end %>
      </.figure>
      <.figure label="Failed attempts" value={if @totals.kept?, do: delimited(@totals.failed), else: "—"}>
        <%= cond do %>
          <% !@totals.kept? -> %>
            {missing(@history)}
          <% @totals.failed == 0 -> %>
            None so far.
          <% @totals.most_failed.failed == @totals.failed -> %>
            All of them on <.release_name release={@totals.most_failed} />.
          <% true -> %>
            {round(@totals.most_failed.failed * 100 / @totals.failed)}% of them on <.release_name release={@totals.most_failed} />.
        <% end %>
      </.figure>
      <.figure label="Typical update" value={duration(@totals.median)}>
        <%= if @totals.median do %>
          Median{release_range(@totals.timed_releases, @rows)}.
        <% else %>
          {if @totals.kept?, do: "No timed updates yet.", else: missing(@history)}
        <% end %>
      </.figure>
      <.figure label="Downloaded" value={bytes(@totals.downloaded)}>
        <%= if @totals.saved > 0 do %>
          Delta updates saved <span class="font-mono">{bytes(@totals.saved)}</span>.
        <% else %>
          No delta updates.
        <% end %>
      </.figure>
    </.figures>

    <section id="stats-releases" aria-labelledby="stats-releases-title" class="overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
      <div class="flex items-baseline justify-between gap-4 px-5 py-4 max-sm:px-4">
        <h2 id="stats-releases-title" class="text-group-title text-content-strong">Releases</h2>
        <p class="text-xs text-content-muted max-sm:hidden">Open one to see its charts.</p>
      </div>
      <table class="w-full text-ui">
        <thead>
          <tr class="h-9 border-y border-line-default bg-surface-muted text-label text-content-faint uppercase">
            <th class="pl-5 text-left font-medium max-sm:pl-4">Release</th>
            <th class="pl-3 text-left font-medium max-sm:hidden">Released</th>
            <th class="pl-3 text-right font-medium">Updated</th>
            <th class="pl-3 text-right font-medium">Succeeded</th>
            <th class="pl-3 text-right font-medium max-sm:pr-4">Failed</th>
            <th class="pl-3 text-right font-medium max-sm:hidden">Typical update</th>
            <th class="pl-3 text-right font-medium max-md:hidden">Downloaded</th>
            <th class="pl-3 text-right font-medium max-md:hidden">Saved by deltas</th>
            <th class="w-10 pr-3 max-sm:hidden"><span class="sr-only">Open</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line-subtle">
          <tr :for={row <- @rows} id={"stats-release-#{row.number}"} class="h-row hover:bg-surface-muted">
            <td class="py-3 pl-5 max-sm:pl-4">
              <span class="flex flex-wrap items-center gap-x-2.5 gap-y-1">
                <span class="w-4 font-mono text-xs text-content-faint">{row.number}</span>
                <.link patch={"#{@path}?release=#{row.number}"} class="font-mono text-content-strong hover:underline">{row.version}</.link>
                <.badge :if={row.current?} tone="notice">Current</.badge>
                <span :if={row.deltas_failed?} class="text-xs text-content-muted">Deltas failed to build</span>
              </span>
            </td>
            <td class="py-3 pl-3 text-content-body max-sm:hidden">{row.released}</td>
            <td class="py-3 pl-3 text-right font-mono whitespace-nowrap text-content-strong">
              {delimited(row.updated)}<span :if={row.newest?} class="font-sans text-content-muted"> so far</span>
            </td>
            <td class="py-3 pl-3 text-right font-mono text-content-body">{succeeded_cell(row.outcomes)}</td>
            <td class={["py-3 pl-3 text-right font-mono max-sm:pr-4", row.most_failed? && "font-semibold text-content-strong", !row.most_failed? && "text-content-body"]}>
              {if row.outcomes, do: delimited(row.outcomes.failed), else: "—"}
            </td>
            <td class="py-3 pl-3 text-right font-mono text-content-body max-sm:hidden">{duration(row.median)}</td>
            <td class="py-3 pl-3 text-right font-mono text-content-body max-md:hidden">{if row.downloaded > 0, do: bytes(row.downloaded), else: "None"}</td>
            <td class="py-3 pl-3 text-right font-mono text-content-body max-md:hidden">{if row.saved > 0, do: bytes(row.saved), else: "None"}</td>
            <td class="py-3 pr-3 text-right max-sm:hidden">
              <.link patch={"#{@path}?release=#{row.number}"} aria-label={"Release #{row.number}"} class="inline-flex text-content-faint hover:text-content-strong">
                <span class="lucide-chevron-right size-4" aria-hidden="true"></span>
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
      <p :if={Enum.any?(@rows, & &1.dashed?)} class="border-t border-line-subtle px-5 py-3 text-xs text-content-muted max-sm:px-4">
        A dash means NervesHub wasn’t keeping that number yet when the release went out.
      </p>
    </section>
    """
  end

  ## Shared pieces

  attr(:release, :map, required: true)

  # A release by its version, and its number too where another release has
  # the same version.
  defp release_name(assigns) do
    ~H"""
    <span class="font-mono">{@release.version}</span><span :if={@release.shared?}>, release {@release.number}</span>
    """
  end

  attr(:id, :string, required: true)
  slot(:inner_block, required: true)

  defp figures(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-2 gap-px overflow-clip rounded-card border border-line-default bg-line-subtle shadow-card @4xl:grid-cols-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  slot(:inner_block, required: true)

  # Every figure here is a value (a share, a time, a size, a count of
  # attempts), so all four are set in mono at the regular weight.
  defp figure(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-2 bg-surface-raised px-5 py-4 max-sm:px-4" data-figure={@label}>
      <span class="truncate text-label text-content-faint uppercase">{@label}</span>
      <div class="flex flex-col gap-0.5">
        <span class={["font-mono text-figure font-normal max-sm:text-figure-sm", if(@value == "—", do: "text-content-faint", else: "text-content-strong")]}>
          {@value}
        </span>
        <span class="text-xs text-content-muted">{render_slot(@inner_block)}</span>
      </div>
    </div>
    """
  end

  attr(:history, :any, required: true)
  attr(:class, :string, default: nil)

  defp pending(assigns) do
    ~H"""
    <p class={["flex items-center justify-center px-5 text-center text-ui text-content-muted", @class]}>
      <%= case @history do %>
        <% :loading -> %>
          <span class="animate-pulse">Loading…</span>
        <% :disabled -> %>
          This server doesn’t keep update outcomes.
        <% _ -> %>
          The update history didn’t answer. Try again in a minute.
      <% end %>
    </p>
    """
  end

  ## Data

  defp detail({:ok, %{attempts: _} = detail}), do: detail
  defp detail(_history), do: nil

  defp versions({:ok, %{versions: versions}}), do: versions
  defp versions(_history), do: %{}

  # Whether the history holds all of a release's outcomes and durations. While
  # it is loading, or can't be read, both are true and the cards say why they
  # are empty.
  defp kept({:ok, %{began: began}}, downloads),
    do: %{
      outcomes: ReleaseStats.kept?(began.outcomes, downloads),
      durations: ReleaseStats.kept?(began.durations, downloads)
    }

  defp kept(_history, _downloads), do: %{outcomes: true, durations: true}

  defp succeeded_value(nil, _kept), do: "—"
  defp succeeded_value(_detail, %{outcomes: false}), do: "—"

  defp succeeded_value(detail, _kept),
    do: percent(detail.attempts.succeeded, detail.attempts.succeeded + detail.attempts.failed)

  defp missing(:loading), do: "Loading…"
  defp missing(:disabled), do: "This server doesn’t keep update outcomes."
  defp missing(:failed), do: "The update history didn’t answer."
  defp missing(_history), do: "NervesHub wasn’t keeping this yet when the release went out."

  @chart_width 1000
  @chart_height 140

  defp timeline(window, detail, steps, now) do
    to = window.to || now
    span = max(DateTime.diff(to, window.from), 1)
    bucket_seconds = detail.timeline.bucket_seconds
    count = max(ceil(span / bucket_seconds), 1)
    bar_width = @chart_width / count

    buckets = detail.timeline.buckets
    max_ok = buckets |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
    max_failed = buckets |> Enum.map(&elem(&1, 2)) |> Enum.max(fn -> 0 end)
    scale = (@chart_height - 4) / max(max_ok + max_failed, 1)
    baseline = 2 + max_ok * scale

    bars =
      for {index, ok, failed} <- buckets, index >= 0 and index < count do
        %{
          x: index * bar_width,
          width: bar_width,
          ok: bar_height(ok, scale),
          failed: bar_height(failed, scale),
          title: "#{delimited(ok)} succeeded, #{delimited(failed)} failed"
        }
      end

    markers =
      steps
      |> Enum.filter(&(DateTime.compare(&1.started_at, window.from) != :lt))
      |> Enum.map(
        &%{names: [&1.name], stopped?: &1.stopped?, x: min(DateTime.diff(&1.started_at, window.from) / span, 1)}
      )
      |> merge_markers()

    %{
      width: @chart_width,
      height: @chart_height,
      baseline: baseline,
      bars: bars,
      steps: markers,
      bucket_name: Map.get(@bucket_names, bucket_seconds, "#{bucket_seconds}-second buckets")
    }
  end

  # Steps that started too close together to label apart share one marker,
  # named for the first and counting the rest.
  defp merge_markers(markers) do
    markers
    |> Enum.chunk_while(
      [],
      fn
        marker, [] -> {:cont, [marker]}
        marker, [first | _] = chunk when marker.x - first.x < 0.12 -> {:cont, [marker | chunk]}
        marker, chunk -> {:cont, Enum.reverse(chunk), [marker]}
      end,
      fn
        [] -> {:cont, []}
        chunk -> {:cont, Enum.reverse(chunk), []}
      end
    )
    |> Enum.map(fn [first | rest] = chunk ->
      name = hd(first.names)

      %{
        x: first.x,
        stopped?: first.stopped?,
        label: if(rest == [], do: name, else: "#{name} +#{length(rest)}"),
        title:
          Enum.map_join(chunk, ", ", fn marker ->
            if marker.stopped?, do: "#{hd(marker.names)} (stopped on failures)", else: hd(marker.names)
          end)
      }
    end)
  end

  # A bucket with any attempts gets a mark that can be seen.
  defp bar_height(0, _scale), do: 0
  defp bar_height(count, scale), do: max(count * scale, 2)

  defp durations(durations) do
    totals = for index <- 0..7, do: Map.get(durations.buckets, index, %{delta: 0, full: 0})
    max_total = totals |> Enum.map(&(&1.delta + &1.full)) |> Enum.max(fn -> 0 end) |> max(1)

    columns =
      totals
      |> Enum.zip(@duration_labels)
      |> Enum.map(fn {%{delta: delta, full: full}, label} ->
        %{
          delta: delta * 100 / max_total,
          full: full * 100 / max_total,
          title: "#{label}: #{delimited(delta + full)} (#{delimited(delta)} delta, #{delimited(full)} full)"
        }
      end)

    markers =
      Enum.reject(
        [
          durations.median && %{x: duration_x(durations.median), label: "Median #{duration(durations.median)}"},
          durations.p90 && durations.p90 != durations.median &&
            %{x: duration_x(durations.p90), label: "9 in 10 within #{duration(durations.p90)}"}
        ],
        &(!&1)
      )
      |> stack_markers()

    %{columns: columns, markers: markers, stacked?: Enum.any?(markers, &(&1.row == 1))}
  end

  # The second label goes on a line of its own when the two are close enough
  # to run into each other.
  defp stack_markers([first, second]) when abs(second.x - first.x) < 0.3,
    do: [Map.put(first, :row, 0), Map.put(second, :row, 1)]

  defp stack_markers(markers), do: Enum.map(markers, &Map.put(&1, :row, 0))

  # Where a duration sits along the columns: its bucket, and how far into it.
  defp duration_x(seconds) do
    starts = ReleaseStats.duration_bucket_starts()
    index = Enum.count(starts, &(&1 <= seconds)) - 1
    start = Enum.at(starts, index)
    width = Enum.at(starts, index + 1, start * 2) - start

    (index + min((seconds - start) / width, 1)) / length(starts)
  end

  # Each bucket's range and its unit, which a phone leaves off.
  defp duration_ticks(),
    do: [
      {"< 2", "m"},
      {"2–4", "m"},
      {"4–6", "m"},
      {"6–8", "m"},
      {"8–10", "m"},
      {"10–15", "m"},
      {"15–30", "m"},
      {"30+", "m"}
    ]

  defp download_rows(sources, versions) do
    {deltas, full} = Enum.split_with(sources, & &1.delta?)

    delta_rows =
      deltas
      |> Enum.sort_by(& &1.updated, :desc)
      |> Enum.map(
        &%{
          delta?: true,
          label: Map.get(versions, &1.source_uuid, "another version"),
          updated: &1.updated,
          downloaded: &1.downloaded
        }
      )

    full_rows =
      case full do
        [] ->
          []

        full ->
          [
            %{
              delta?: false,
              label: nil,
              updated: Enum.sum_by(full, & &1.updated),
              downloaded: Enum.sum_by(full, & &1.downloaded)
            }
          ]
      end

    delta_rows ++ full_rows
  end

  defp reasons(detail) do
    sorted = Enum.sort_by(detail.reasons, & &1.count, :desc)
    {shown, rest} = Enum.split(sorted, 5)

    %{
      shown: shown,
      max: shown |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end),
      rest: Enum.sum_by(rest, & &1.count),
      rest_reasons: length(rest)
    }
  end

  defp silent_reason(:abandoned), do: "Rejoined on the old firmware, saying nothing"
  defp silent_reason(:expired), do: "Stopped making progress and timed out"
  defp silent_reason(:ignored), do: "Declined the update, saying nothing"
  defp silent_reason(:failed), do: "Failed, saying nothing"

  defp status_label(:abandoned), do: "Abandoned"
  defp status_label(:expired), do: "Expired"
  defp status_label(:ignored), do: "Declined the update"
  defp status_label(:failed), do: "Failed"

  defp source_rows(detail, versions, deltas) do
    rows =
      detail.sources
      |> Enum.map(fn source ->
        version = Map.get(versions, source.uuid)

        %{
          label: version || "Unknown",
          version: version,
          succeeded: source.succeeded,
          failed: source.failed,
          median: source.median,
          download: download(Map.get(deltas, source.uuid))
        }
      end)
      |> Enum.sort_by(&version_key/1, :desc)

    if length(rows) > @source_rows + 1 do
      {shown, rest} = Enum.split(rows, @source_rows)

      shown ++
        [
          %{
            label: count_noun(length(rest), "older version", "older versions"),
            version: nil,
            succeeded: Enum.sum_by(rest, & &1.succeeded),
            failed: Enum.sum_by(rest, & &1.failed),
            median: nil,
            download: nil
          }
        ]
    else
      rows
    end
  end

  # Newest version first, and what NervesHub can't name last.
  defp version_key(%{version: nil}), do: {0, nil}

  defp version_key(%{version: version}) do
    case Version.parse(version) do
      {:ok, parsed} -> {2, parsed}
      :error -> {1, version}
    end
  end

  defp download(%{status: :completed, size: size}), do: %{delta?: true, note: bytes(size), alert?: false}

  defp download(%{status: status}) when status in [:failed, :timed_out],
    do: %{delta?: false, note: "delta failed to build", alert?: true}

  defp download(%{status: :processing}), do: %{delta?: false, note: "delta still building", alert?: false}
  defp download(nil), do: %{delta?: false, note: "no delta", alert?: false}

  defp release_rows(windows, downloads, history, group, time_zone) do
    {outcomes, began} =
      case history do
        {:ok, %{releases: releases, began: began}} -> {releases, began}
        _ -> {nil, nil}
      end

    newest_id = windows |> List.first() |> then(&(&1 && &1.release.id))

    rows =
      Enum.map(windows, fn %{release: release} = window ->
        release_downloads = Map.get(downloads, release.id, %{updated: 0, downloaded: 0, saved: 0, first_at: nil})

        %{
          id: release.id,
          number: release.number,
          version: release.firmware.version,
          released: DateTimes.to_local_string(window.from, time_zone, :short_date, false),
          current?: release.id == group.current_deployment_release_id,
          newest?: release.id == newest_id,
          deltas_failed?: release.delta_status == :failed,
          updated: release_downloads.updated,
          downloaded: release_downloads.downloaded,
          saved: release_downloads.saved,
          most_failed?: false
        }
        |> Map.merge(row_outcomes(outcomes, began, release.id, release_downloads))
      end)

    most_failed =
      rows
      |> Enum.filter(&(&1.outcomes && &1.outcomes.failed > 0))
      |> Enum.max_by(& &1.outcomes.failed, fn -> nil end)

    Enum.map(rows, &%{&1 | most_failed?: most_failed != nil and length(rows) > 1 and &1.id == most_failed.id})
  end

  # A release's outcomes and median where the history has all of them, and
  # whether any are missing. Before the history answers, none are shown and
  # none are missing.
  defp row_outcomes(nil, _began, _release_id, _downloads), do: %{outcomes: nil, median: nil, dashed?: false}

  defp row_outcomes(outcomes, began, release_id, downloads) do
    outcomes_kept? = ReleaseStats.kept?(began.outcomes, downloads)
    durations_kept? = ReleaseStats.kept?(began.durations, downloads)
    release_outcomes = Map.get(outcomes, release_id, %{succeeded: 0, failed: 0, rescheduled: 0, median: nil})

    %{
      outcomes: if(outcomes_kept?, do: release_outcomes),
      median: if(outcomes_kept? and durations_kept?, do: release_outcomes.median),
      dashed?: not (outcomes_kept? and durations_kept?)
    }
  end

  defp totals(rows, history) do
    with_outcomes = Enum.filter(rows, & &1.outcomes)

    shared_versions = rows |> Enum.frequencies_by(& &1.version) |> Map.filter(fn {_version, count} -> count > 1 end)

    most_failed =
      with_outcomes
      |> Enum.max_by(& &1.outcomes.failed, fn -> nil end)
      |> then(
        &(&1 &&
            %{
              failed: &1.outcomes.failed,
              version: &1.version,
              number: &1.number,
              shared?: Map.has_key?(shared_versions, &1.version)
            })
      )

    %{
      succeeded: Enum.sum_by(with_outcomes, & &1.outcomes.succeeded),
      failed: Enum.sum_by(with_outcomes, & &1.outcomes.failed),
      kept?: with_outcomes != [],
      attempted_releases: for(row <- with_outcomes, row.outcomes.succeeded + row.outcomes.failed > 0, do: row.number),
      timed_releases: rows |> Enum.filter(& &1.median) |> Enum.map(& &1.number),
      most_failed: most_failed,
      median:
        case history do
          {:ok, %{median: median}} -> median
          _ -> nil
        end,
      downloaded: Enum.sum_by(rows, & &1.downloaded),
      saved: Enum.sum_by(rows, & &1.saved)
    }
  end

  # A dash is kept for numbers the history doesn't have; a release with no
  # attempts to count leaves the cell empty.
  defp succeeded_cell(nil), do: "—"
  defp succeeded_cell(%{succeeded: 0, failed: 0}), do: ""
  defp succeeded_cell(outcomes), do: percent(outcomes.succeeded, outcomes.succeeded + outcomes.failed)

  # ", releases 3 to 7" when the numbers leave some releases out.
  defp release_range([], _rows), do: ""

  defp release_range(numbers, rows) do
    cond do
      length(numbers) == length(rows) -> ""
      length(numbers) == 1 -> ", release #{hd(numbers)}"
      true -> ", releases #{Enum.min(numbers)} to #{Enum.max(numbers)}"
    end
  end

  ## Words

  defp release_label(window, group) do
    current = if window.release.id == group.current_deployment_release_id, do: " · current"
    "#{window.release.firmware.version} · Release #{window.release.number}#{current}"
  end

  defp window_text(:all, windows, _now, time_zone) do
    oldest = List.last(windows)

    "#{count_noun(length(windows), "release", "releases")} since #{DateTimes.to_local_string(oldest.from, time_zone, :short_date, false)}"
  end

  defp window_text(window, windows, now, time_zone) do
    released = "Released #{DateTimes.to_local_string(window.from, time_zone, :short_datetime, false)}"

    case window.to do
      nil ->
        "#{released} · out for #{span_words(DateTime.diff(now, window.from))}"

      to ->
        replaced_by = Enum.find(windows, &(&1.from == to))

        "#{released} · replaced by #{replaced_by.release.firmware.version} after #{span_words(DateTime.diff(to, window.from))}"
    end
  end

  # Over all releases, when some show a dash, says from when the history has
  # its numbers.
  defp note(:all, {:ok, %{began: %{outcomes: %DateTime{} = outcomes} = began}}, time_zone, true) do
    case began.durations do
      nil ->
        "Outcomes are kept from #{day(outcomes, time_zone)}, so older releases show a dash."

      durations ->
        "Outcomes are kept from #{day(outcomes, time_zone)} and update times from #{day(durations, time_zone)}, so older releases show a dash."
    end
  end

  defp note(_selected, _history, _time_zone, _dashed?),
    do: "Counts update attempts. A device that tried twice counts twice."

  defp day(at, time_zone), do: DateTimes.to_local_string(at, time_zone, :short_date, false)

  defp span_words(seconds) when seconds < 3600, do: count_noun(max(div(seconds, 60), 1), "minute", "minutes")
  defp span_words(seconds) when seconds < 2 * 86_400, do: count_noun(div(seconds, 3600), "hour", "hours")
  defp span_words(seconds), do: count_noun(div(seconds, 86_400), "day", "days")

  @doc false
  # Public for its tests.
  def duration(nil), do: "—"
  def duration(seconds) when seconds < 60, do: "#{seconds}s"
  def duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m #{pad(rem(seconds, 60))}s"
  def duration(seconds), do: "#{div(seconds, 3600)}h #{pad(div(rem(seconds, 3600), 60))}m"

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  @doc false
  # Decimal units, as the firmware list writes sizes.
  def bytes(nil), do: "—"
  def bytes(bytes) when bytes >= 1_000_000_000_000, do: "#{decimal(bytes / 1_000_000_000_000)} TB"
  def bytes(bytes) when bytes >= 1_000_000_000, do: "#{decimal(bytes / 1_000_000_000)} GB"
  def bytes(bytes) when bytes >= 1_000_000, do: "#{decimal(bytes / 1_000_000)} MB"
  def bytes(bytes) when bytes >= 1_000, do: "#{decimal(bytes / 1_000)} KB"
  def bytes(bytes), do: "#{bytes} B"

  defp decimal(number), do: :erlang.float_to_binary(number, decimals: 1)

  @doc false
  def percent(_part, 0), do: "—"
  def percent(0, _total), do: "0%"
  def percent(part, part), do: "100%"

  def percent(part, total) do
    # Never round a shortfall up to 100%.
    "#{decimal(min(part * 100 / total, 99.9))}%"
  end

  defp share(_part, 0), do: 0
  defp share(part, whole), do: Float.round(part * 100 / whole, 2)
end
