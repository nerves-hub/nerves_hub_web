defmodule NervesHubWeb.Components.FleetComposition do
  @moduledoc """
  The fleet composition on a product's Insights page: three proportion bars
  (connection, health and firmware version), a table crossing health and
  connection with firmware version, and the "Stands out" card beside it.

  Each takes what `NervesHub.Insights` returns, and every count links to the
  devices list filtered to the devices it counts.

  The layout follows the width it is given rather than the window's, through
  container queries: `bars/1` is its own container, and `version_table/1` and
  `stands_out/1` sit in one the page provides (`@container`), so the table
  can give way to a list, and the card move above it, as the room runs out.
  """
  use NervesHubWeb, :component

  import NervesHubWeb.Components.Fleet, only: [delimited: 1]

  alias NervesHub.Insights

  # Version colours, in the order versions are listed. Chart 2 (orange) and
  # 6 (green) sit next to warning and healthy in the other bars, so they come
  # last.
  @version_palette [1, 3, 4, 5, 2, 6]

  @not_healthy ~s(health_status != "healthy")

  @healthy "var(--color-chart-3)"
  @warning "var(--color-chart-4)"
  @alert "var(--color-chart-alert)"
  @unknown "var(--color-line-control)"

  attr(:composition, :map, required: true, doc: "from `NervesHub.Insights.composition/2`")
  attr(:rows, :list, required: true, doc: "from `NervesHub.Insights.versions/1`")
  attr(:unit, :atom, required: true, values: [:count, :percent], doc: "how the legends show each figure")
  attr(:devices_path, :string, required: true, doc: "the product's devices list, which the legends link into")

  @doc """
  What the fleet is made of: one bar each for connection, health and firmware
  version, with a legend under each linking to the devices it counts.

  From 640px wide the title and summary of each bar sit in a column to its
  left; below that they sit on one line over a thinner bar.
  """
  def bars(assigns) do
    %{composition: composition, rows: rows} = assigns
    total = composition.total

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:connection, connection_segments(composition.connection, assigns.devices_path))
      |> assign(:health, health_segments(composition.health, assigns.devices_path))
      |> assign(:firmware, firmware_segments(rows, assigns.devices_path))
      |> assign(
        :newest,
        composition.newest_version && Enum.find(composition.versions, &(&1.version == composition.newest_version))
      )

    ~H"""
    <section id="fleet-composition" class="@container flex flex-col">
      <div class="flex items-end justify-between gap-4 pb-3 @min-[640px]:pb-5">
        <div class="flex flex-col gap-1.5 @min-[640px]:gap-1">
          <div class="text-label text-content-faint uppercase @min-[640px]:font-semibold">What the fleet is made of</div>
          <div class="flex items-baseline gap-2 @min-[640px]:gap-2.5">
            <span class="font-mono text-figure-lg text-content-strong @min-[640px]:text-figure-xl">{delimited(@total)}</span>
            <span class="text-ui/4.5 text-content-muted @min-[640px]:text-sm">
              {if @total == 1, do: "device", else: "devices"}<span class="hidden @min-[640px]:inline">, each counted once in every bar</span>
            </span>
          </div>
        </div>
        <div id="composition-unit" role="group" aria-label="Show the fleet composition as" class="mb-0.75 flex shrink-0 overflow-hidden rounded-md border border-line-control @min-[640px]:mb-0">
          <.segment phx-click="set-composition-unit" phx-value-unit="count" selected={@unit == :count} class="py-1.25 @min-[640px]:px-3 @min-[640px]:py-1.5 @min-[640px]:text-ui/4.5">Count</.segment>
          <.segment
            phx-click="set-composition-unit"
            phx-value-unit="percent"
            selected={@unit == :percent}
            aria-label="Percent"
            class="py-1.25 @min-[640px]:px-3 @min-[640px]:py-1.5 @min-[640px]:text-ui/4.5"
          >
            <span aria-hidden="true" class="@min-[640px]:hidden">%</span><span aria-hidden="true" class="hidden @min-[640px]:inline">Percent</span>
          </.segment>
        </div>
      </div>

      <.composition_row id="composition-connection" title="Connection" segments={@connection} total={@total} unit={@unit}>
        <:summary>
          <span class="font-mono text-content-strong">{percent(@composition.connection.online, @total)}</span> online
        </:summary>
      </.composition_row>

      <.composition_row id="composition-health" title="Health" segments={@health} total={@total} unit={@unit}>
        <:summary>
          <span class="font-mono text-content-strong">{percent(@composition.health.healthy, @total)}</span> healthy
        </:summary>
      </.composition_row>

      <.composition_row id="composition-firmware" title="Firmware" segments={@firmware} total={@total} unit={@unit}>
        <:summary :if={@newest}>
          <span class="font-mono text-content-strong">{percent(@newest.count, @total)}</span> on latest
        </:summary>
      </.composition_row>
    </section>
    """
  end

  attr(:selected, :boolean, required: true)
  attr(:class, :any, default: nil, doc: "sizes the button for its control")
  attr(:rest, :global, include: ~w(value))
  slot(:inner_block, required: true)

  @doc """
  One button of the bordered segmented controls on the Insights page: the
  composition's Count and Percent, and the trends' period and adoption view.

  Every button after the first draws the rule between it and the one before.
  `phx-click` and its value go on the button.
  """
  def segment(assigns) do
    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@selected)}
      class={[
        "flex cursor-pointer items-center justify-center gap-1.5 px-2.5 text-xs text-content-muted not-first:border-l not-first:border-line-control hover:text-content-strong",
        "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus-ring",
        "aria-pressed:bg-surface-muted aria-pressed:font-medium aria-pressed:text-content-strong",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:segments, :list, required: true)
  attr(:total, :integer, required: true)
  attr(:unit, :atom, required: true)
  slot(:summary)

  defp composition_row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex flex-col gap-2 border-t border-line-subtle py-3.5",
        "@min-[640px]:flex-row @min-[640px]:items-start @min-[640px]:gap-0 @min-[640px]:py-4.5",
        "@min-[640px]:first-of-type:border-line-default @min-[640px]:last-of-type:border-b"
      ]}
    >
      <div class="flex items-baseline justify-between gap-3 @min-[640px]:w-50 @min-[640px]:shrink-0 @min-[640px]:flex-col @min-[640px]:justify-start @min-[640px]:gap-0.5">
        <div class="text-ui/4.5 font-semibold text-content-strong">{@title}</div>
        <div class="text-xs text-content-muted">{render_slot(@summary)}</div>
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-2 @min-[640px]:gap-2.5">
        <div class="flex h-2.5 gap-px overflow-hidden rounded-[3px] @min-[640px]:h-7 @min-[640px]:gap-0.5" role="img" aria-label={bar_label(@title, @segments, @total)}>
          <div :for={segment <- @segments} :if={segment.count > 0} class="h-full min-w-0.75" style={"flex: #{segment.count} 1 0%; background: #{segment.color}"}></div>
        </div>
        <div class="flex flex-wrap gap-x-3.5 gap-y-1 @min-[640px]:gap-x-7">
          <.legend_item :for={segment <- @segments} :if={segment.count > 0 or segment[:always]} segment={segment} total={@total} unit={@unit} />
        </div>
      </div>
    </div>
    """
  end

  attr(:segment, :map, required: true)
  attr(:total, :integer, required: true)
  attr(:unit, :atom, required: true)

  # The folded versions have no filter to link to, so their item is plain.
  defp legend_item(%{segment: %{href: nil}} = assigns) do
    ~H"""
    <span class="flex items-center gap-1.25 text-xs text-content-muted @min-[640px]:gap-1.5">
      <.legend_body segment={@segment} total={@total} unit={@unit} />
    </span>
    """
  end

  defp legend_item(assigns) do
    ~H"""
    <.link navigate={@segment.href} class="group flex items-center gap-1.25 text-xs text-content-muted @min-[640px]:gap-1.5">
      <.legend_body segment={@segment} total={@total} unit={@unit} />
    </.link>
    """
  end

  attr(:segment, :map, required: true)
  attr(:total, :integer, required: true)
  attr(:unit, :atom, required: true)

  # A phone's narrower legend wraps under shorter labels ("7–14 d" for "Not
  # seen 7–14 d"), so a segment can carry a `short` one for under 640px.
  defp legend_body(assigns) do
    ~H"""
    <span class="size-2 shrink-0 rounded-[2px]" style={"background: #{@segment.color}"}></span>
    <span class={["group-hover:underline", @segment[:mono] && "font-mono"]}>
      <span :if={@segment[:short]} class="@min-[640px]:hidden">{@segment.short}</span><span class={@segment[:short] && "hidden @min-[640px]:inline"}>{@segment.label}</span>
    </span>
    <span class="font-mono text-content-strong">{figure(@segment.count, @total, @unit)}</span>
    """
  end

  defp connection_segments(counts, devices_path) do
    filters = Insights.connection_filters()

    [
      %{
        label: "Online",
        count: counts.online,
        color: @healthy,
        href: devices_href(devices_path, filters.online),
        always: true
      },
      %{
        label: "Offline under 7 d",
        short: "Offline <7 d",
        count: counts.recent,
        color: "var(--color-chart-other)",
        href: devices_href(devices_path, filters.recent)
      },
      %{
        label: "Not seen 7–14 d",
        short: "7–14 d",
        count: counts.week,
        color: @warning,
        href: devices_href(devices_path, filters.week)
      },
      %{
        label: "Not seen 14 d+",
        short: "14 d+",
        count: counts.stale,
        color: @alert,
        href: devices_href(devices_path, filters.stale)
      },
      # Shown only when some devices have never connected, so the bar still
      # adds up to the fleet.
      %{
        label: "Never connected",
        short: "Never",
        count: counts.never,
        color: @unknown,
        href: devices_href(devices_path, filters.never)
      }
    ]
  end

  defp health_segments(counts, devices_path) do
    for {status, label, color} <- [
          {:healthy, "Healthy", @healthy},
          {:warning, "Warning", @warning},
          {:unhealthy, "Unhealthy", @alert},
          {:unknown, "Unknown", @unknown}
        ] do
      %{
        label: label,
        count: counts[status],
        color: color,
        href: devices_href(devices_path, health_status: status),
        always: status == :healthy
      }
    end
  end

  defp firmware_segments(rows, devices_path) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} ->
      %{
        label: row_label(row),
        count: row.count,
        color: version_color(row, index),
        href: row_href(row, devices_path),
        mono: row.kind == :version
      }
    end)
  end

  attr(:composition, :map, required: true, doc: "from `NervesHub.Insights.composition/2`")
  attr(:rows, :list, required: true, doc: "from `NervesHub.Insights.versions/1`")
  attr(:stands_out, :map, default: nil, doc: "from `NervesHub.Insights.stands_out/1`, to mark the version it names")
  attr(:devices_path, :string, required: true)

  @doc """
  Health and connection by firmware version: a row per version, with each
  cell shaded by its share of that version's devices.

  In a container under 787px, the table's width, it becomes a list with a
  small health bar and the share not healthy per version.
  """
  def version_table(assigns) do
    flagged =
      case assigns.stands_out do
        %{kind: :version, row: row} -> row.version
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:indexed, Enum.with_index(assigns.rows))
      |> assign(:flagged, flagged)
      |> assign(:offline, Enum.sum_by(assigns.rows, & &1.offline))
      |> assign(:columns, [:healthy, :warning, :unhealthy, :unknown, :offline])

    ~H"""
    <section id="version-health" class="flex min-w-0 flex-col">
      <div class="hidden flex-col @min-[787px]:flex">
        <div class="flex items-baseline justify-between gap-4 pb-3">
          <h2 class="text-list-title text-content-strong">Health and connection by firmware version</h2>
          <p class="text-xs text-content-faint">Shading is the share of that version's devices</p>
        </div>

        <table class="w-196.75 table-fixed border-collapse">
          <thead>
            <tr class="h-8 border-b border-line-default text-left text-label tracking-[0.04em] text-content-faint uppercase">
              <th class="w-24 pl-2 font-medium">Version</th>
              <th class="w-52.75 font-medium">Devices</th>
              <th :for={heading <- ~w(Healthy Warning Unhealthy Unknown Offline)} class="w-24 pr-3 text-right font-medium">{heading}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{row, index} <- @indexed}
              id={"version-row-#{index}"}
              data-flagged={flagged?(row, @flagged)}
              class={["h-10 border-b border-line-subtle font-mono text-ui/4.5 last:border-line-default", flagged?(row, @flagged) && "shadow-[inset_2px_0_0_var(--color-chart-alert)]"]}
            >
              <td class="pl-2">
                <.version_name row={row} color={version_color(row, index)} devices_path={@devices_path} />
              </td>
              <td>
                <div class="flex items-center gap-2.5">
                  <span class="w-10 shrink-0 text-right text-content-strong">{delimited(row.count)}</span>
                  <span class="h-1.5 w-35 shrink-0 rounded-[3px] bg-surface-muted">
                    <span class="block h-full rounded-[3px]" style={"width: #{row.count / @composition.total * 100}%; background: #{version_color(row, index)}"}></span>
                  </span>
                </div>
              </td>
              <.shaded_cell value={row.health.healthy} count={row.count} href={cell_href(row, :healthy, @devices_path)} />
              <.shaded_cell
                value={row.health.warning}
                count={row.count}
                shade="warning"
                emphasis={flagged?(row, @flagged) && "text-warning-content"}
                href={cell_href(row, :warning, @devices_path)}
              />
              <.shaded_cell
                value={row.health.unhealthy}
                count={row.count}
                shade="alert"
                weight={2}
                emphasis={flagged?(row, @flagged) && "text-alert-content"}
                href={cell_href(row, :unhealthy, @devices_path)}
              />
              <.shaded_cell value={row.health.unknown} count={row.count} shade="offline" weight={0.6} class="text-content-muted" href={cell_href(row, :unknown, @devices_path)} />
              <.shaded_cell
                value={row.offline}
                count={row.count}
                shade="offline"
                max={25}
                emphasis={flagged?(row, @flagged) && "text-content-strong"}
                href={cell_href(row, :offline, @devices_path)}
              />
            </tr>
          </tbody>
          <tfoot :if={length(@rows) > 1}>
            <tr class="h-10 font-mono text-ui/4.5 font-semibold text-content-strong">
              <td class="pl-2 font-sans">Total</td>
              <td><span class="inline-block w-10 text-right">{delimited(@composition.total)}</span></td>
              <td :for={{value, column} <- Enum.zip(totals(@composition, @offline), @columns)} class="p-0 text-right">
                <.link :if={value > 0} navigate={cell_href(nil, column, @devices_path)} class={cell_link_class()}>{delimited(value)}</.link>
                <span :if={value == 0} class="block pr-3">{delimited(value)}</span>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <div class="flex flex-col @min-[787px]:hidden">
        <h2 class="text-list-title text-content-strong">Health by firmware version</h2>
        <div class="flex h-9.5 items-center gap-2.5 border-b border-line-default pt-2 text-label tracking-[0.04em] text-content-faint uppercase">
          <span class="w-19 shrink-0">Version</span>
          <span class="w-10 shrink-0 text-right">Count</span>
          <span class="flex-1">Health</span>
          <span class="w-19 shrink-0 text-right tracking-[0.02em] whitespace-pre">Not healthy</span>
        </div>
        <ul class="flex flex-col">
          <li
            :for={{row, index} <- @indexed}
            data-flagged={flagged?(row, @flagged)}
            class={["flex h-11 items-center gap-2.5 border-b border-line-subtle last:border-line-default", flagged?(row, @flagged) && "bg-(--color-chart-alert)/4"]}
          >
            <span class="w-19 shrink-0"><.version_name row={row} color={version_color(row, index)} devices_path={@devices_path} /></span>
            <span class="w-10 shrink-0 text-right font-mono text-ui/4.5 text-content-strong">{delimited(row.count)}</span>
            <span class="min-w-0 flex-1"><.health_bar health={row.health} class="h-2 rounded-[2px]" /></span>
            <span class={["w-19 shrink-0 text-right font-mono text-ui/4.5", if(flagged?(row, @flagged), do: "font-semibold text-alert-content", else: "text-content-strong")]}>
              {percent(Insights.not_healthy(row.health), row.count)}
            </span>
          </li>
        </ul>
        <div class="flex flex-wrap gap-x-3 gap-y-1 pt-2.5">
          <span :for={{label, color} <- health_colors()} class="flex items-center gap-1.25 text-xs text-content-muted">
            <span class="size-2 shrink-0 rounded-[2px]" style={"background: #{color}"}></span>
            {label}
          </span>
        </div>
        <p class="pt-2 text-xs text-content-faint">Not healthy is warning, unhealthy or unknown. Tap a version to list its devices.</p>
      </div>
    </section>
    """
  end

  attr(:row, :map, required: true)
  attr(:color, :string, required: true)
  attr(:devices_path, :string, required: true)

  defp version_name(assigns) do
    assigns = assign(assigns, :href, row_href(assigns.row, assigns.devices_path))

    ~H"""
    <span class="flex min-w-0 items-center gap-2">
      <span class="size-2 shrink-0 rounded-[2px]" style={"background: #{@color}"}></span>
      <.link :if={@href} navigate={@href} class={["truncate hover:underline", version_text_class(@row)]}>{row_label(@row)}</.link>
      <span :if={!@href} class={["truncate", version_text_class(@row)]}>{row_label(@row)}</span>
    </span>
    """
  end

  defp version_text_class(%{kind: :version}), do: "font-mono text-ui/4.5 text-content-strong"
  defp version_text_class(_row), do: "font-sans text-ui/4.5 text-content-muted"

  attr(:value, :integer, required: true)
  attr(:count, :integer, required: true, doc: "the version's devices, which the shading is a share of")

  attr(:shade, :string,
    default: nil,
    values: [nil, "warning", "alert", "offline"],
    doc: "the shading's colour; nil leaves the cell plain"
  )

  attr(:weight, :any,
    default: 1,
    doc: "how much the share counts for, so an unhealthy device can shade more than a warning one"
  )

  attr(:href, :string, default: nil, doc: "the devices the figure counts; nil for a figure that can't be listed")
  attr(:max, :integer, default: 30, doc: "the strongest shading, as a percentage")
  attr(:emphasis, :any, default: nil, doc: "a text colour class that also makes the figure bold")
  attr(:class, :any, default: "text-content-strong")

  defp shaded_cell(assigns) do
    ~H"""
    <td class="p-0 text-right" style={cell_style(@value, @count, @shade, @weight, @max)}>
      <.link :if={@href && @value > 0} navigate={@href} class={[cell_link_class(), figure_class(@value, @emphasis, @class)]}>{delimited(@value)}</.link>
      <span :if={!(@href && @value > 0)} class={["block pr-3", figure_class(@value, @emphasis, @class)]}>{delimited(@value)}</span>
    </td>
    """
  end

  defp figure_class(0, _emphasis, _class), do: "text-content-faint"
  defp figure_class(_value, nil, class), do: class
  defp figure_class(_value, false, class), do: class
  defp figure_class(_value, emphasis, _class), do: [emphasis, "font-semibold"]

  # The whole cell is the target, not just the figure, so a narrow number is
  # as easy to hit as a wide one.
  defp cell_link_class() do
    "block h-10 pr-3 leading-10 hover:underline hover:bg-(--color-content-strong)/4 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus-ring"
  end

  # The devices behind one cell: the row's version and the column's health,
  # or not online for the Offline column. The folded others span several
  # versions, which the list can't filter on at once, so their cells aren't
  # links. A nil row is the Total row, the whole fleet.
  defp cell_href(%{kind: :others}, _column, _devices_path), do: nil

  defp cell_href(row, column, devices_path) do
    version =
      case row do
        nil -> []
        %{kind: :unknown} -> [firmware_version: "Unknown"]
        %{version: version} -> [firmware_version: version]
      end

    filter =
      case column do
        :offline -> [advanced_query: ~s(connection != "connected")]
        status -> [health_status: status]
      end

    devices_href(devices_path, version ++ filter)
  end

  # A share under 1% leaves the cell plain, so a lone device in a big version
  # doesn't tint its cell. Above that the tint follows the share, between a
  # faint 3% and `max`, and the dark theme strengthens it (`--shade-strength`)
  # so it reads on a dark surface.
  defp cell_style(_value, _count, nil, _weight, _max), do: nil

  defp cell_style(value, count, shade, weight, max) do
    share = value / count * weight * 100

    if share >= 1 do
      alpha = share |> max(3) |> min(max) |> Kernel.*(1.0) |> Float.round(1)

      "background: color-mix(in oklab, #{shade_color(shade)} calc(#{alpha}% * var(--shade-strength)), transparent)"
    end
  end

  defp shade_color("warning"), do: "var(--color-chart-4)"
  defp shade_color("alert"), do: "var(--color-chart-alert)"
  defp shade_color("offline"), do: "var(--color-shade-offline)"

  defp totals(composition, offline) do
    %{health: health} = composition
    [health.healthy, health.warning, health.unhealthy, health.unknown, offline]
  end

  defp flagged?(%{kind: :version, version: version}, version), do: true
  defp flagged?(_row, _flagged), do: false

  defp health_colors(unknown \\ @unknown) do
    [{"Healthy", @healthy}, {"Warning", @warning}, {"Unhealthy", @alert}, {"Unknown", unknown}]
  end

  attr(:health, :map, required: true)
  attr(:unknown, :string, default: @unknown, doc: "the colour for unknown health")
  attr(:class, :any, required: true, doc: "the bar's height and corners")

  defp health_bar(assigns) do
    ~H"""
    <div class={["flex gap-px overflow-hidden", @class]}>
      <div
        :for={{{_label, color}, status} <- Enum.zip(health_colors(@unknown), [:healthy, :warning, :unhealthy, :unknown])}
        :if={@health[status] > 0}
        class="h-full min-w-0.5"
        style={"flex: #{@health[status]} 1 0%; background: #{color}"}
      >
      </div>
    </div>
    """
  end

  attr(:stands_out, :map, required: true, doc: "from `NervesHub.Insights.stands_out/1`")
  attr(:composition, :map, required: true)
  attr(:devices_path, :string, required: true)

  @doc """
  The "Stands out" card: the version whose devices are least healthy against
  the fleet, or why there isn't one.
  """
  def stands_out(%{stands_out: %{kind: :version}} = assigns) do
    %{row: row, rate: rate, fleet_rate: fleet_rate, not_healthy: fleet_not_healthy} = assigns.stands_out
    %{composition: composition} = assigns
    row_not_healthy = Insights.not_healthy(row.health)

    assigns =
      assign(assigns,
        row: row,
        rate: rate,
        fleet_rate: fleet_rate,
        row_not_healthy: row_not_healthy,
        fleet_share: percent(row.count, composition.total, 0),
        unhealthy_share: unhealthy_share(row, composition, fleet_not_healthy),
        comparison: comparison(row, composition, fleet_not_healthy),
        href: devices_href(assigns.devices_path, firmware_version: row.version)
      )

    ~H"""
    <.stands_out_card id="stands-out" accent="border-l-(--color-chart-alert)" label="Stands out" label_class="text-alert-content">
      <:headline>
        <span class="font-mono">{@row.version}</span> is {@fleet_share} of the fleet and {@unhealthy_share}.
      </:headline>
      {delimited(@row_not_healthy)} of its {delimited(@row.count)} devices are warning, unhealthy or unknown. {@comparison}
      <:extra>
        <div class="flex flex-col gap-1.5">
          <.meter value={@rate} color="var(--color-chart-alert)" value_class="text-alert-content">
            Not healthy on <span class="font-mono">{@row.version}</span>
          </.meter>
          <.meter value={@fleet_rate} color="var(--color-content-faint)" class="pt-1.5">Fleet average</.meter>
        </div>
      </:extra>
      <:action>
        <.button type="link" style="contrast" navigate={@href}>View {delimited(@row.count)} {if @row.count == 1, do: "device", else: "devices"}</.button>
      </:action>
    </.stands_out_card>
    """
  end

  def stands_out(%{stands_out: %{kind: :even}} = assigns) do
    %{rows: rows, fleet_rate: fleet_rate} = assigns.stands_out
    rates = Enum.map(rows, &Insights.rate/1)
    # the scale leaves room past the highest rate, so the longest bar never fills its track
    scale = rates |> Enum.max() |> max(fleet_rate) |> Kernel.*(1.5)

    assigns =
      assign(assigns,
        rows: Enum.with_index(rows),
        fleet_rate: fleet_rate,
        scale: scale,
        close: Enum.all?(rates, &(abs(&1 - fleet_rate) <= 0.01)),
        not_healthy: assigns.stands_out.not_healthy,
        min_devices: assigns.stands_out.min_devices,
        href: devices_href(assigns.devices_path, advanced_query: @not_healthy)
      )

    ~H"""
    <.stands_out_card id="stands-out" accent="border-l-line-control" label="Stands out" label_class="text-content-faint">
      <:headline>Nothing stands out.</:headline>
      {if @close, do: "Every version is within a point of", else: "No version of #{@min_devices} or more devices is twice"} the fleet's {percent(@fleet_rate)} not healthy, so the {delimited(@not_healthy)} {if @not_healthy ==
                                                                                                                                                                                                                   1,
                                                                                                                                                                                                                 do:
                                                                                                                                                                                                                   "device that needs a look isn't",
                                                                                                                                                                                                                 else:
                                                                                                                                                                                                                   "devices that need a look aren't"} tied to one firmware.
      <:extra>
        <div class="flex flex-col gap-2 pt-0.5">
          <div :for={{row, index} <- @rows} class="flex items-center gap-2.5">
            <span class={["w-14 shrink-0 truncate text-xs", if(row.kind == :version, do: "font-mono text-content-strong", else: "text-content-muted")]}>
              {row_label(row)}
            </span>
            <span class="relative h-1.5 w-50 min-w-0 shrink rounded-[3px] bg-surface-muted">
              <span class="absolute inset-y-0 left-0 rounded-[3px]" style={"width: #{Insights.rate(row) / @scale * 100}%; background: #{version_color(row, index)}"}></span>
              <span class="absolute -top-0.75 h-3 w-[1.5px] bg-content-strong" style={"left: #{@fleet_rate / @scale * 100}%"}></span>
            </span>
            <span class="shrink-0 font-mono text-xs text-content-strong">{percent(Insights.rate(row))}</span>
          </div>
          <div class="flex items-center gap-1.5 pt-0.5 text-xs text-content-faint">
            <span class="h-3 w-[1.5px] shrink-0 bg-content-strong"></span>
            <span>Fleet, <span class="font-mono">{percent(@fleet_rate)}</span> not healthy</span>
          </div>
        </div>
      </:extra>
      <:action>
        <.button type="link" navigate={@href}>View {delimited(@not_healthy)} not healthy</.button>
      </:action>
    </.stands_out_card>
    """
  end

  def stands_out(%{stands_out: %{kind: :all_healthy}} = assigns) do
    %{total: total, offline: offline} = assigns.stands_out

    assigns =
      assign(assigns,
        total: total,
        offline: offline,
        href: devices_href(assigns.devices_path, advanced_query: ~s(connection != "connected"))
      )

    ~H"""
    <.stands_out_card id="stands-out" accent="border-l-(--color-chart-3)" label="All healthy" label_class="text-success-content">
      <:headline>{if @total == 1, do: "The one device is healthy.", else: "All #{delimited(@total)} devices are healthy."}</:headline>
      No version has a warning, unhealthy or unknown device.
      <span :if={@offline > 0}>{if @offline == 1, do: "The 1 offline was", else: "The #{delimited(@offline)} offline were"} healthy when they last reported.</span>
      <:extra>
        <.meter value={1.0} label="100%" color="var(--color-chart-3)" value_class="text-success-content">Healthy</.meter>
      </:extra>
      <:action :if={@offline > 0}>
        <.button type="link" navigate={@href}>View {delimited(@offline)} offline</.button>
      </:action>
    </.stands_out_card>
    """
  end

  def stands_out(%{stands_out: %{kind: :single}} = assigns) do
    %{row: row, not_healthy: not_healthy} = assigns.stands_out

    assigns =
      assign(assigns,
        row: row,
        not_healthy: not_healthy,
        href: devices_href(assigns.devices_path, advanced_query: @not_healthy)
      )

    ~H"""
    <.stands_out_card id="stands-out" accent="border-l-line-control" label="Stands out" label_class="text-content-faint">
      <:headline>Nothing to compare yet.</:headline>
      <%= if @row.kind == :version do %>
        Every device runs <span class="font-mono">{@row.version}</span>, so there is no other version to measure it against. When a second version ships, this card compares them.
      <% else %>
        No device has reported its firmware version yet, so there are no versions to compare.
      <% end %>
      <:extra>
        <div class="flex flex-col gap-2">
          <div :if={@row.kind == :version} class="text-xs text-content-muted">Health on <span class="font-mono">{@row.version}</span></div>
          <.health_bar health={@row.health} unknown="var(--color-chart-other)" class="h-2 rounded-[3px]" />
          <div class="flex flex-wrap gap-x-3.5 gap-y-1">
            <span
              :for={{{label, color}, status} <- Enum.zip(health_colors("var(--color-chart-other)"), [:healthy, :warning, :unhealthy, :unknown])}
              :if={@row.health[status] > 0}
              class="flex items-center gap-1.5 text-xs text-content-muted"
            >
              <span class="size-2 shrink-0 rounded-[2px]" style={"background: #{color}"}></span>
              <span><span class="font-mono">{delimited(@row.health[status])}</span> {String.downcase(label)}</span>
            </span>
          </div>
        </div>
      </:extra>
      <:action :if={@not_healthy > 0}>
        <.button type="link" navigate={@href}>View {delimited(@not_healthy)} not healthy</.button>
      </:action>
    </.stands_out_card>
    """
  end

  # "21% of its unhealthy devices" when the fleet has some; a fleet whose
  # trouble is all warnings and unknowns has none to take a share of, so the
  # share is then of the devices that aren't healthy.
  defp unhealthy_share(row, %{health: %{unhealthy: unhealthy}}, _fleet_not_healthy) when unhealthy > 0,
    do: "#{percent(row.health.unhealthy, unhealthy, 0)} of its unhealthy devices"

  defp unhealthy_share(row, _composition, fleet_not_healthy),
    do: "#{percent(Insights.not_healthy(row.health), fleet_not_healthy, 0)} of its devices that aren't healthy"

  # How the newest version compares, as "1 in N" devices not healthy. When the
  # flagged version is the newest, or there is no newest, the whole fleet is
  # the comparison instead.
  defp comparison(row, composition, fleet_not_healthy) do
    case Enum.find(composition.versions, &(&1.version == composition.newest_version)) do
      %{version: version} = newest when version != row.version ->
        case Insights.not_healthy(newest.health) do
          0 -> "On #{version} none are."
          count -> "On #{version} it is 1 in #{round(newest.count / count)}."
        end

      _ ->
        "Across the fleet it is 1 in #{round(composition.total / fleet_not_healthy)}."
    end
  end

  attr(:id, :string, required: true)
  attr(:accent, :string, required: true, doc: "the left edge's border colour class")
  attr(:label, :string, required: true)
  attr(:label_class, :string, required: true)
  slot(:headline, required: true)
  slot(:inner_block, required: true, doc: "the sentence under the headline")
  slot(:extra)
  slot(:action)

  # The card sits in the page's `@container`: a ringed card under 640px, as
  # on a phone, and a plain one beside or above the table from there.
  defp stands_out_card(assigns) do
    ~H"""
    <aside
      id={@id}
      class={[
        "flex flex-col gap-3 rounded-card border-l-3 bg-surface-raised p-4 shadow-[0_0_0_1px_var(--color-line-subtle)]",
        "@min-[640px]:gap-3.5 @min-[640px]:p-5 @min-[640px]:shadow-none",
        @accent
      ]}
    >
      <div class={["text-label font-semibold uppercase", @label_class]}>{@label}</div>
      <p class="text-item-title/6 font-medium text-content-strong @min-[640px]:text-lg/6.5">{render_slot(@headline)}</p>
      <p class="text-ui/5 text-content-muted">{render_slot(@inner_block)}</p>
      <div :if={@extra != []} class="pt-0.5 @min-[640px]:pt-1">{render_slot(@extra)}</div>
      <div :if={@action != []} class="flex gap-2 pt-1 @min-[640px]:pt-1.5">{render_slot(@action)}</div>
    </aside>
    """
  end

  attr(:value, :float, required: true, doc: "from 0 to 1")
  attr(:label, :string, default: nil, doc: "the figure shown, if not the value as a percentage")
  attr(:color, :string, required: true)
  attr(:value_class, :string, default: "text-content-strong")
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  defp meter(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1.5", @class]}>
      <div class="flex justify-between text-xs">
        <span class="text-content-muted">{render_slot(@inner_block)}</span>
        <span class={["font-mono", @value_class]}>{@label || percent(@value)}</span>
      </div>
      <div class="h-1.5 rounded-[3px] bg-surface-muted">
        <div class="h-full rounded-[3px]" style={"width: #{@value * 100}%; background: #{@color}"}></div>
      </div>
    </div>
    """
  end

  @doc """
  The colour of a firmware breakdown row at position `index`, the same in the
  composition bar, the table and the "Stands out" card.
  """
  @spec version_color(map(), non_neg_integer()) :: String.t()
  def version_color(%{kind: :others}, _index), do: "var(--color-chart-other)"
  def version_color(%{kind: :unknown}, _index), do: "var(--color-line-strong)"
  def version_color(_row, index), do: "var(--color-chart-#{Enum.at(@version_palette, index, 6)})"

  @doc """
  The colour for a version's name written beside its chart colour, as the
  trends row's adoption chart labels its bands: a darker shade of the same
  hue, so it reads as text.
  """
  def version_label_color(%{kind: :others}, _index), do: "var(--color-content-muted)"
  def version_label_color(%{kind: :unknown}, _index), do: "var(--color-content-muted)"
  def version_label_color(_row, index), do: "var(--color-chart-#{Enum.at(@version_palette, index, 6)}-label)"

  defp row_label(%{kind: :version, version: version}), do: version
  defp row_label(%{kind: :unknown}), do: "Unknown"
  defp row_label(%{kind: :others, folded: folded}), do: "#{folded} others"

  # The folded versions have no single filter to send the devices list.
  defp row_href(%{kind: :version, version: version}, devices_path),
    do: devices_href(devices_path, firmware_version: version)

  defp row_href(%{kind: :unknown}, devices_path), do: devices_href(devices_path, firmware_version: "Unknown")
  defp row_href(%{kind: :others}, _devices_path), do: nil

  defp devices_href(devices_path, params), do: devices_path <> "?" <> URI.encode_query(params)

  defp bar_label(title, segments, total) do
    parts =
      segments
      |> Enum.filter(&(&1.count > 0))
      |> Enum.map_join(", ", &"#{&1.label} #{percent(&1.count, total)}")

    "#{title}: #{parts}"
  end

  defp figure(count, _total, :count), do: delimited(count)
  defp figure(count, total, :percent), do: percent(count, total)

  @doc """
  `count` as a percentage of `total`, to `decimals` places. A rate from 0 to
  1 can be given on its own.
  """
  @spec percent(number(), number(), non_neg_integer()) :: String.t()
  def percent(count, total, decimals \\ 1)
  def percent(_count, 0, _decimals), do: "0%"
  def percent(count, total, decimals), do: format_percent(count / total * 100, decimals)

  @spec percent(float()) :: String.t()
  def percent(rate), do: format_percent(rate * 100, 1)

  defp format_percent(value, 0), do: "#{round(value)}%"
  defp format_percent(value, decimals), do: "#{:erlang.float_to_binary(value * 1.0, decimals: decimals)}%"
end
