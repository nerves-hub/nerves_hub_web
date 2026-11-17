defmodule NervesHubWeb.Components.FleetTrends do
  @moduledoc """
  The trends row on a product's Insights page: firmware adoption, update
  outcomes, and the fleet's online and healthy shares over a period, drawn
  from `NervesHub.Insights.Trends` as SVG on the server.

  Each chart is laid out in a fixed coordinate space (680 wide for adoption
  and updates, 375 for the two lines) and stretched to the width it is
  given, so strokes are drawn with `vector-effect: non-scaling-stroke` and
  end dots as zero-length round-capped strokes, which stay round when the
  chart is stretched. Text is HTML placed over the chart, never SVG text.

  When the newest version was released, if that falls in the period, is
  marked on every chart with the same dashed line, unless the viewer has
  turned release annotations off.
  """
  use NervesHubWeb, :component

  import NervesHubWeb.CoreComponents, only: [switch: 1]

  alias NervesHubWeb.Components.FleetComposition

  # The adoption and updates charts' coordinate space.
  @wide 680
  @adoption_height 120
  @updates_height 56
  @updates_baseline 41

  # The online and healthy charts'.
  @narrow 375
  @line_height 96

  # The smallest gap between two labels in the adoption chart's gutter.
  @label_gap 13

  @titles %{"24h" => "Last 24 hours", "14d" => "Last 14 days", "4w" => "Last 4 weeks", "90d" => "Last 90 days"}
  @segments [{"24h", "24 h"}, {"14d", "14 d"}, {"4w", "4 w"}, {"90d", "90 d"}]

  attr(:trends, :map, required: true, doc: "from `NervesHub.Insights.Trends.trends/5`")
  attr(:composition, :map, required: true, doc: "from `NervesHub.Insights.composition/2`")
  attr(:rows, :list, required: true, doc: "from `NervesHub.Insights.versions/1`")
  attr(:adoption_view, :atom, required: true, values: [:stacked, :lines])
  attr(:releases, :boolean, default: true, doc: "whether to mark the release on the charts")

  @doc """
  The row: a heading with the period control, then adoption over updates on
  the left and the online and healthy lines on the right. Under 1167px the
  two lines move below, side by side from 640px; under 640px each chart
  drops its gutter for a legend or a heading above it.
  """
  def row(assigns) do
    %{trends: trends} = assigns
    count = length(trends.buckets)

    assigns =
      assigns
      |> assign(:title, @titles[trends.period])
      |> assign(:segments, @segments)
      |> assign(:release, assigns.releases && release(trends))
      |> assign(:axis, ticks(trends))
      |> assign(:adoption, adoption(trends, assigns.composition, assigns.rows))
      |> assign(:updates, updates(trends.updates, count))
      |> assign(:online, line(trends.online, count))
      |> assign(:healthy, line(trends.healthy, count))
      |> assign(:wide, @wide)
      |> assign(:narrow, @narrow)
      |> assign(:adoption_height, @adoption_height)
      |> assign(:updates_height, @updates_height)
      |> assign(:updates_baseline, @updates_baseline)
      |> assign(:line_height, @line_height)

    ~H"""
    <section
      id="trends"
      class="@container -mx-4 flex flex-col gap-2.5 border-t border-line-default px-4 pt-7 sm:mx-0 sm:gap-3.5 sm:border-0 sm:px-0 sm:pt-0"
    >
      <div class="flex flex-col gap-2.5 @min-[640px]:flex-row @min-[640px]:items-baseline @min-[640px]:justify-between">
        <div class="flex items-baseline justify-between gap-3 @min-[640px]:justify-start">
          <h2 class="text-list-title text-content-strong">{@title}</h2>
          <span :if={@release} id="trends-release" class="flex items-center gap-1.5 text-xs text-content-muted">
            <span class="h-3 w-0 shrink-0 border-l-[1.5px] border-dashed border-indigo-500"></span>
            <span class="font-mono">{@release.version}</span> released {@release.label}
          </span>
        </div>
        <div class="flex items-center gap-4">
          <.switch id="release-annotations" label="Releases" checked={@releases} phx-click="toggle-release-annotations" />
          <div id="trends-period" role="group" aria-label="Period" class="flex flex-1 overflow-clip rounded-md border border-line-control @min-[640px]:min-w-0 @min-[640px]:flex-none">
            <.segment
              :for={{period, label} <- @segments}
              event="set-trends-period"
              value={period}
              selected={@trends.period == period}
              class="flex-1 py-1.25 @min-[640px]:flex-none @min-[640px]:py-1"
            >
              {label}
            </.segment>
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-4 @min-[1167px]:flex-row @min-[1167px]:items-start @min-[1167px]:gap-8">
        <div class="flex min-w-0 flex-col gap-2.5 pt-4 sm:border-t sm:border-line-default sm:pt-3.5 @min-[1167px]:w-190 @min-[1167px]:shrink-0">
          <.adoption adoption={@adoption} view={@adoption_view} release={@release} width={@wide} height={@adoption_height} />
          <.updates updates={@updates} release={@release} width={@wide} height={@updates_height} baseline={@updates_baseline} />
          <.axis axis={@axis} />
        </div>

        <div class="grid min-w-0 gap-4 sm:gap-4.5 @min-[640px]:grid-cols-2 @min-[640px]:gap-8 @min-[1167px]:flex-1 @min-[1167px]:grid-cols-1 @min-[1167px]:gap-4.5">
          <.line_chart id="trends-online" title="Online" line={@online} release={@release} width={@narrow} height={@line_height} />
          <.line_chart id="trends-healthy" title="Healthy" line={@healthy} release={@release} width={@narrow} height={@line_height} />
        </div>
      </div>
    </section>
    """
  end

  attr(:event, :string, required: true)
  attr(:value, :string, required: true)
  attr(:selected, :boolean, required: true)
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  # One button of a segmented control. Every one after the first draws the
  # rule between it and the one before.
  defp segment(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      value={@value}
      aria-pressed={to_string(@selected)}
      class={[
        "flex cursor-pointer items-center justify-center gap-1.5 px-2.5 text-xs text-content-muted not-first:border-l not-first:border-line-control hover:text-content-strong",
        "focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-focus-ring",
        "aria-pressed:bg-surface-muted aria-pressed:font-medium aria-pressed:text-content-strong",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr(:adoption, :map, required: true)
  attr(:view, :atom, required: true)
  attr(:release, :map, default: nil)
  attr(:width, :integer, required: true)
  attr(:height, :integer, required: true)

  defp adoption(assigns) do
    ~H"""
    <div id="trends-adoption" class="flex flex-col gap-2.5">
      <div class="flex items-start justify-between gap-3 @min-[640px]:items-end @min-[640px]:pr-20">
        <div class="flex min-w-0 flex-col gap-0.5">
          <h3 class="text-ui/4.5 font-medium text-content-muted sm:text-content-body">Firmware adoption</h3>
          <div :if={@adoption.headline} class="flex min-w-0 flex-wrap items-baseline gap-x-2">
            <span class="font-mono text-figure-md text-content-strong">{@adoption.headline.share}</span>
            <span class="text-xs text-content-muted">
              on <span class="font-mono">{@adoption.headline.version}</span><span class="max-sm:hidden">, {@adoption.headline.since}</span>
            </span>
          </div>
        </div>
        <div id="adoption-view" role="group" aria-label="Adoption chart" class="mb-0.5 flex shrink-0 overflow-clip rounded-md border border-line-control">
          <.segment event="set-adoption-view" value="stacked" selected={@view == :stacked} class="py-1.25 sm:py-1">
            <span class="lucide-chart-area size-3.5 max-sm:hidden" aria-hidden="true"></span> Stacked
          </.segment>
          <.segment event="set-adoption-view" value="lines" selected={@view == :lines} class="py-1.25 sm:py-1">
            <span class="lucide-chart-line size-3.5 max-sm:hidden" aria-hidden="true"></span> Lines
          </.segment>
        </div>
      </div>

      <div class="flex gap-3">
        <div class="relative h-24 min-w-0 flex-1 @min-[640px]:h-30">
          <svg viewBox={"0 0 #{@width} #{@height}"} preserveAspectRatio="none" class="block size-full" aria-hidden="true">
            <%= if @view == :stacked do %>
              <rect width={@width} height={@height} style="fill: var(--color-line-control)" />
              <path :for={band <- @adoption.bands} d={band.area} style={"fill: #{band.color}"} />
              <line
                :if={@release}
                x1={@release.x * @width}
                x2={@release.x * @width}
                y1="0"
                y2={@height}
                vector-effect="non-scaling-stroke"
                stroke-width="1.5"
                stroke-dasharray="4 3"
                style="stroke: var(--color-surface)"
              />
            <% else %>
              <line
                :for={y <- @adoption.grid}
                x1="0"
                x2={@width}
                y1={y}
                y2={y}
                vector-effect="non-scaling-stroke"
                stroke-dasharray={if y != List.last(@adoption.grid), do: "2 3"}
                style="stroke: var(--color-line-default)"
              />
              <.release_line :if={@release} x={@release.x * @width} height={@height} />
              <g :for={band <- Enum.reverse(@adoption.bands)}>
                <path
                  d={band.line}
                  fill="none"
                  vector-effect="non-scaling-stroke"
                  stroke-width={band.stroke}
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  style={"stroke: #{band.color}"}
                />
                <.dot x={band.end_x} y={band.end_y} color={band.color} />
              </g>
            <% end %>
          </svg>

          <div :if={@view == :lines} class="pointer-events-none absolute inset-y-0 left-1 font-mono text-[10px]/3.5 text-content-faint">
            <span :for={{label, y} <- @adoption.grid_labels} class="absolute" style={"top: calc(#{y / @height * 100}% - 7px)"}>{label}</span>
          </div>

          <span
            :if={@release}
            class={[
              "absolute rounded-[3px] bg-indigo-500 px-1.25 py-px font-mono text-[10px]/3.5 text-white",
              if(@view == :stacked, do: "bottom-1 @min-[640px]:bottom-2", else: "top-2")
            ]}
            style={"left: calc(#{@release.x * 100}% + 4px)"}
          >
            {@release.version}
          </span>
        </div>

        <div class="relative w-17 shrink-0 @max-[639px]:hidden">
          <span
            :for={label <- if(@view == :stacked, do: @adoption.labels, else: @adoption.line_labels)}
            class={["absolute left-0 flex gap-1.5 font-mono text-[11px]/3.25 whitespace-nowrap", label.newest && "font-semibold"]}
            style={"top: #{label.top}px"}
          >
            <span style={"color: #{label.color}"}>{label.version}</span>
            <span class={if label.newest, do: "text-content-strong", else: "text-content-muted"}>{label.value}</span>
          </span>
        </div>
      </div>

      <div class="flex flex-wrap gap-1 @min-[640px]:hidden">
        <span :for={label <- @adoption.legend} class="flex w-21 shrink-0 items-center gap-1.5 font-mono text-[11px]/3.5">
          <span class="size-2 shrink-0 rounded-[2px]" style={"background: #{label.swatch}"}></span>
          <span class={if label.newest, do: "text-content-strong", else: "text-content-muted"}>{label.version}</span>
          <span class={if label.newest, do: "font-semibold text-content-strong", else: "text-content-muted"}>{label.value}</span>
        </span>
      </div>
    </div>
    """
  end

  attr(:updates, :map, required: true)
  attr(:release, :map, default: nil)
  attr(:width, :integer, required: true)
  attr(:height, :integer, required: true)
  attr(:baseline, :integer, required: true)

  defp updates(assigns) do
    ~H"""
    <div id="trends-updates" class="flex flex-col gap-2.5 pt-1.5">
      <div class="flex justify-between text-xs @min-[640px]:hidden">
        <span class="text-content-muted">Updates</span>
        <span class="font-mono">
          <span class="text-success-content">{@updates.succeeded} ok</span>
          <span class="text-content-faint">·</span>
          <span class="text-alert-content">{@updates.failed} failed</span>
        </span>
      </div>
      <div class="flex gap-3">
        <svg viewBox={"0 0 #{@width} #{@height}"} preserveAspectRatio="none" class="block h-14 min-w-0 flex-1" aria-hidden="true">
          <g :for={bar <- @updates.bars}>
            <rect :if={bar.ok > 0} x={bar.x * @width} y={@baseline - 1 - bar.ok} width={bar.width * @width} height={bar.ok} rx="1" style="fill: var(--color-chart-3)" />
            <rect :if={bar.failed > 0} x={bar.x * @width} y={@baseline + 1} width={bar.width * @width} height={bar.failed} rx="1" style="fill: var(--color-chart-alert)" />
          </g>
          <line x1="0" x2={@width} y1={@baseline} y2={@baseline} vector-effect="non-scaling-stroke" class="stroke-zinc-600 light:stroke-zinc-400" />
          <.release_line :if={@release} x={@release.x * @width} height={@height} width="1.5" />
        </svg>
        <div class="flex w-17 shrink-0 flex-col justify-between text-[11px]/3.25 @max-[639px]:hidden">
          <span class="flex flex-col">
            <span class="text-content-muted">Updates</span>
            <span class="font-mono text-success-content">{@updates.succeeded} ok</span>
          </span>
          <span class="font-mono text-alert-content">{@updates.failed} failed</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:axis, :list, required: true)

  # Wider than a phone each label sits over its bucket; on a phone the first
  # starts at the left edge and the last ends at the right, as the board
  # has them.
  defp axis(assigns) do
    ~H"""
    <div class="flex gap-3">
      <div class="relative h-3.5 min-w-0 flex-1 font-mono text-[11px]/3.5 text-content-faint">
        <span
          :for={{tick, index} <- Enum.with_index(@axis)}
          class={[
            "absolute -translate-x-1/2 whitespace-nowrap",
            index == 0 && "max-sm:left-0! max-sm:translate-x-0",
            index == length(@axis) - 1 && "max-sm:right-0 max-sm:left-auto! max-sm:translate-x-0"
          ]}
          style={"left: #{tick.x * 100}%"}
        >
          {tick.label}
        </span>
      </div>
      <div class="w-17 shrink-0 @max-[639px]:hidden"></div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:line, :map, required: true)
  attr(:release, :map, default: nil)
  attr(:width, :integer, required: true)
  attr(:height, :integer, required: true)

  defp line_chart(assigns) do
    ~H"""
    <div id={@id} class="flex min-w-0 flex-col gap-2 sm:border-t sm:border-line-default sm:pt-3.5">
      <div class="flex items-baseline justify-between gap-3">
        <div class="flex items-baseline gap-2">
          <h3 class="text-ui/4.5 text-content-strong sm:font-medium sm:text-content-body">{@title}</h3>
          <span class="font-mono text-figure-xs text-content-strong">{@line.value}</span>
          <span class={["font-mono text-xs", @line.delta_class]}>{@line.delta}</span>
        </div>
        <span class="font-mono text-[11px]/3.5 text-content-faint">{@line.range}</span>
      </div>
      <svg viewBox={"0 0 #{@width} #{@height}"} preserveAspectRatio="none" class="block h-16 w-full sm:h-24" aria-hidden="true">
        <line x1="0" x2={@width} y1={@height - 0.5} y2={@height - 0.5} vector-effect="non-scaling-stroke" style="stroke: var(--color-line-default)" />
        <path d={@line.area} style="fill: color-mix(in oklab, var(--color-chart-3) 10%, transparent)" />
        <path
          d={@line.path}
          fill="none"
          vector-effect="non-scaling-stroke"
          stroke-width="1.75"
          stroke-linejoin="round"
          style="stroke: var(--color-chart-3)"
        />
        <.release_line :if={@release} x={@release.x * @width} height={@height} dash="3 3" />
        <.dot x={@line.end_x} y={@line.end_y} color="var(--color-chart-3)" />
      </svg>
    </div>
    """
  end

  attr(:x, :any, required: true)
  attr(:height, :integer, required: true)
  attr(:width, :string, default: "1.25")
  attr(:dash, :string, default: "4 3")

  defp release_line(assigns) do
    ~H"""
    <line
      x1={@x}
      x2={@x}
      y1="0"
      y2={@height}
      vector-effect="non-scaling-stroke"
      stroke-width={@width}
      stroke-dasharray={@dash}
      style="stroke: var(--color-release)"
    />
    """
  end

  attr(:x, :any, required: true)
  attr(:y, :any, required: true)
  attr(:color, :string, required: true)

  # A zero-length stroke with round caps: a 6px dot that stays round however
  # far the chart is stretched.
  defp dot(assigns) do
    ~H"""
    <path d={"M#{@x} #{@y}h0"} vector-effect="non-scaling-stroke" stroke-width="6" stroke-linecap="round" style={"stroke: #{@color}"} />
    """
  end

  ## Geometry

  # The middle of bucket `index` of `count`, as a fraction of the width.
  defp center(index, count), do: (index + 0.5) / count

  defp release(%{release: nil}), do: nil

  defp release(%{release: release, buckets: buckets, unit: unit}) do
    count = length(buckets)
    span = if unit == :hour, do: 3600, else: 86_400

    index = Enum.find_index(buckets, &DateTime.before?(release.at, &1.until)) || count - 1
    bucket = Enum.at(buckets, index)
    within = DateTime.diff(release.at, bucket.from, :second) / span

    %{
      version: release.version,
      x: (index + min(max(within, 0), 1)) / count,
      index: index,
      at: release.at,
      label: Calendar.strftime(release.at, "%b %-d")
    }
  end

  # A label every few buckets, so they don't crowd: the first, then every
  # step, then the last as "Today" or "Now", leaving out one that would
  # crowd it.
  defp ticks(%{buckets: buckets, unit: unit}) do
    count = length(buckets)
    step = %{24 => 6, 14 => 3, 28 => 7, 90 => 15}[count] || max(div(count, 5), 1)
    last = count - 1

    indexes = Enum.filter(0..last//step, &(last - &1 >= step / 2)) ++ [last]

    {ticks, _} =
      Enum.map_reduce(indexes, nil, fn index, previous_month ->
        from = Enum.at(buckets, index).from

        label =
          cond do
            index == last and unit == :hour -> "Now"
            index == last -> "Today"
            unit == :hour -> Calendar.strftime(from, "%H:00")
            previous_month == from.month -> Calendar.strftime(from, "%-d")
            true -> Calendar.strftime(from, "%b %-d")
          end

        {%{label: label, x: center(index, count)}, from.month}
      end)

    ticks
  end

  defp adoption(trends, composition, rows) do
    count = length(trends.buckets)
    total = max(trends.total, 1)

    named =
      rows
      |> Enum.with_index()
      |> Enum.filter(fn {row, _index} -> row.kind == :version end)
      |> Enum.map(fn {row, index} ->
        shares = Enum.map(trends.adoption, &(Map.get(&1, row.version, 0) / total))

        %{
          version: row.version,
          color: FleetComposition.version_color(row, index),
          label_color: FleetComposition.version_label_color(row, index),
          shares: shares,
          newest: row.version == composition.newest_version
        }
      end)

    bands = bands(named, count)

    %{
      bands: bands,
      grid: Enum.map([1, 0.75, 0.5, 0.25, 0], &lines_y/1),
      grid_labels: [{"100%", lines_y(1)}, {"75", lines_y(0.75)}, {"50", lines_y(0.5)}, {"25", lines_y(0.25)}],
      labels: gutter_labels(bands, & &1.stacked_mid),
      line_labels: gutter_labels(bands, & &1.end_y),
      legend:
        Enum.map(bands, fn band ->
          %{version: band.version, value: band.value, swatch: band.color, newest: band.newest}
        end),
      headline: headline(trends, named, composition)
    }
  end

  # Bands stacked from the bottom in the composition's order, so the largest
  # version sits on the baseline. Whatever the named versions leave is the
  # chart's grey background.
  defp bands(named, count) do
    {bands, _} =
      Enum.map_reduce(named, List.duplicate(0.0, count), fn version, below ->
        above = Enum.zip_with(below, version.shares, &(&1 + &2))
        last = List.last(version.shares)

        band =
          Map.merge(version, %{
            area: area(above, below, count),
            line: polyline(Enum.map(version.shares, &lines_y/1), count, @wide),
            stroke: 1.5,
            end_x: center(count - 1, count) * @wide,
            end_y: lines_y(last),
            stacked_mid: @adoption_height * (1 - (List.last(above) + List.last(below)) / 2),
            value: :erlang.float_to_binary(last * 100, decimals: 1)
          })

        {band, above}
      end)

    bands
    |> Enum.with_index()
    |> Enum.map(fn
      {band, 0} -> %{band | stroke: 2.5}
      {band, 1} -> %{band | stroke: 1.75}
      {band, _} -> band
    end)
  end

  defp lines_y(share), do: 116 - share * 112

  defp stacked_y(share), do: Float.round(@adoption_height * (1 - share), 2)

  # One band of the stack: along its top from left to right, flat to both
  # edges, and back along the top of the band below.
  defp area(above, below, count) do
    top = edge_points(above, count)
    bottom = below |> edge_points(count) |> Enum.reverse()

    "M" <> Enum.map_join(top ++ bottom, " L", fn {x, y} -> "#{x} #{y}" end) <> " Z"
  end

  defp edge_points(shares, count) do
    middle =
      shares
      |> Enum.with_index()
      |> Enum.map(fn {share, index} -> {round2(center(index, count) * @wide), stacked_y(share)} end)

    [{0, stacked_y(hd(shares))}] ++ middle ++ [{@wide, stacked_y(List.last(shares))}]
  end

  defp polyline(ys, count, width) do
    "M" <>
      (ys
       |> Enum.with_index()
       |> Enum.map_join(" L", fn {y, index} -> "#{round2(center(index, count) * width)} #{round2(y)}" end))
  end

  # The gutter beside the stack names each band at its middle on the right,
  # or at its line's end in the lines view, pushed apart where they would
  # overlap.
  defp gutter_labels(bands, wanted) do
    bands
    |> Enum.map(&{&1, wanted.(&1)})
    |> spread()
    |> Enum.map(fn {band, center} ->
      %{
        version: band.version,
        value: band.value,
        color: band.label_color,
        newest: band.newest,
        top: round2(center - 6.5)
      }
    end)
  end

  # Places labels at their wanted centres, or as near as they can be while
  # keeping @label_gap apart: labels that would overlap form a cluster,
  # centred on the average of where they want to be.
  defp spread(items) do
    items
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.reduce([], fn {item, wanted}, clusters -> merge([%{items: [{item, wanted}]} | clusters]) end)
    |> Enum.reverse()
    |> Enum.flat_map(&place/1)
  end

  defp merge([newer, older | rest] = clusters) do
    if last_center(older) + @label_gap > first_center(newer) do
      merge([%{items: older.items ++ newer.items} | rest])
    else
      clusters
    end
  end

  defp merge(clusters), do: clusters

  defp place(%{items: items}) do
    first = first_center(%{items: items})
    items |> Enum.with_index() |> Enum.map(fn {{item, _}, index} -> {item, first + index * @label_gap} end)
  end

  defp first_center(%{items: items}) do
    mean = Enum.sum_by(items, &elem(&1, 1)) / length(items)
    mean - (length(items) - 1) * @label_gap / 2
  end

  defp last_center(%{items: items} = cluster), do: first_center(cluster) + (length(items) - 1) * @label_gap

  defp headline(_trends, [], _composition), do: nil

  defp headline(trends, named, composition) do
    case Enum.find(named, & &1.newest) do
      nil ->
        nil

      newest ->
        now = List.last(newest.shares)
        release = release(trends)

        {from, since} =
          if release do
            before = if release.index > 0, do: Enum.at(newest.shares, release.index - 1), else: 0.0
            {before, DateTime.diff(trends.now, release.at, :second)}
          else
            {hd(newest.shares), DateTime.diff(trends.now, hd(trends.buckets).from, :second)}
          end

        %{
          share: percent(now),
          version: composition.newest_version,
          since: "from #{percent(from)} in #{span(since)}"
        }
    end
  end

  defp span(seconds) when seconds < 86_400, do: plural(max(div(seconds, 3600), 1), "hour")
  defp span(seconds), do: plural(round(seconds / 86_400), "day")

  defp plural(1, unit), do: "1 #{unit}"
  defp plural(count, unit), do: "#{count} #{unit}s"

  defp updates(buckets, count) do
    max_ok = buckets |> Enum.map(& &1.succeeded) |> Enum.max(fn -> 0 end)
    max_failed = buckets |> Enum.map(& &1.failed) |> Enum.max(fn -> 0 end)

    # One scale for both, so a day's failures read against its successes,
    # fitted to whichever runs out of room first.
    scale =
      [max_ok > 0 && 38.5 / max_ok, max_failed > 0 && 14 / max_failed]
      |> Enum.filter(& &1)
      |> Enum.min(fn -> 0 end)

    width = 0.795 / count

    bars =
      buckets
      |> Enum.with_index()
      |> Enum.map(fn {bucket, index} ->
        %{
          x: index / count + (1 / count - width) / 2,
          width: width,
          ok: bar_height(bucket.succeeded, scale, 1.5),
          failed: bar_height(bucket.failed, scale, 1.4)
        }
      end)

    %{
      bars: bars,
      succeeded: delimited(Enum.sum_by(buckets, & &1.succeeded)),
      failed: delimited(Enum.sum_by(buckets, & &1.failed))
    }
  end

  defp bar_height(0, _scale, _least), do: 0
  defp bar_height(count, scale, least), do: max(round2(count * scale), least)

  # A share over the period: scaled to its own range, rounded out to half a
  # point, with room above and below the line.
  defp line(shares, count) do
    percents = Enum.map(shares, &(&1 * 100))
    low = Float.floor(Enum.min(percents) * 2) / 2
    high = Float.ceil(Enum.max(percents) * 2) / 2
    {low, high} = if high - low < 1, do: {max(high - 1, 0.0), max(high, 1.0)}, else: {low, high}

    ys = Enum.map(percents, &(86 - (&1 - low) / (high - low) * 72))
    path = polyline(ys, count, @narrow)
    first_x = round2(center(0, count) * @narrow)
    last_x = round2(center(count - 1, count) * @narrow)

    delta = Float.round(List.last(percents) - hd(percents), 1)

    %{
      path: path,
      area: "#{path} L#{last_x} #{@line_height} L#{first_x} #{@line_height} Z",
      end_x: last_x,
      end_y: round2(List.last(ys)),
      value: percent(List.last(shares)),
      range: "#{trim(low)}–#{trim(high)}%",
      delta: delta_label(delta),
      delta_class:
        cond do
          delta < 0 -> "text-alert-content"
          delta > 0 -> "text-success-content"
          true -> "text-content-faint"
        end
    }
  end

  defp delta_label(delta) when delta < 0, do: "−#{:erlang.float_to_binary(-delta, decimals: 1)} pt"
  defp delta_label(delta) when delta > 0, do: "+#{:erlang.float_to_binary(delta, decimals: 1)} pt"
  defp delta_label(_delta), do: "0.0 pt"

  defp percent(share), do: :erlang.float_to_binary(share * 100, decimals: 1) <> "%"

  defp trim(value) do
    if value == Float.round(value),
      do: Integer.to_string(trunc(value)),
      else: :erlang.float_to_binary(value, decimals: 1)
  end

  defp round2(value), do: Float.round(value * 1.0, 2)

  defp delimited(number), do: Number.Delimit.number_to_delimited(number, precision: 0)
end
