defmodule NervesHubWeb.Components.DevicePage.ComponentReadings do
  @moduledoc """
  How a component's readings and state are drawn on the device page's
  Components tab: the list's Reading column, the value on a card, and the
  Readings and State sections of the side panel.

  Readings are named by the device, so names and units are a convention
  rather than a lookup (docs/components.md): `temperature` is degrees
  Celsius, `humidity` and `battery` percent, `co2` ppm. A name this module
  doesn't know is shown as sent, with no unit.

  There are no thresholds yet, so nothing here is coloured as good or bad: a
  state's values are told apart by how long each lasted, the longest darkest.
  """

  use NervesHubWeb, :component

  alias NervesHub.Devices.DeviceComponent
  alias NervesHubWeb.Components.DateTimes

  # Readings that describe the radio or the power rather than what the
  # component measures go after the rest.
  @housekeeping ~w(battery voltage rssi lqi linkquality)

  @labels %{
    "co2" => "CO₂",
    "pm1" => "PM1",
    "pm2_5" => "PM2.5",
    "pm10" => "PM10",
    "voc" => "VOC",
    "hcho" => "Formaldehyde",
    "rssi" => "RSSI",
    "lqi" => "Link quality",
    "linkquality" => "Link quality"
  }

  @units %{
    "temperature" => "°C",
    "humidity" => "%",
    "battery" => "%",
    "co2" => "ppm",
    "voltage" => "V",
    "pm1" => "µg/m³",
    "pm2_5" => "µg/m³",
    "pm10" => "µg/m³",
    "rssi" => "dBm"
  }

  # Most time first. The first two are the neutrals a two-state timeline
  # needs; the rest only come out for a state with more values than that.
  @segment_colors ~w(bg-content-strong bg-line-strong bg-chart-1 bg-chart-2 bg-chart-4 bg-chart-5)

  ## Names, units and values

  @doc "A reading or state name as a person reads it: `co2` is CO₂, `door_contact` is Door contact."
  @spec label(String.t()) :: String.t()
  def label(name), do: Map.get_lazy(@labels, name, fn -> name |> String.replace("_", " ") |> capitalize() end)

  @doc "The unit a reading's name implies, or `nil`."
  @spec unit(String.t()) :: String.t() | nil
  def unit(name), do: Map.get(@units, name)

  @doc """
  A reading's value, to as many places as tell it apart: 1,240, 21.4, 0.31.
  """
  @spec value(number()) :: String.t()
  def value(number) when is_integer(number), do: value(number / 1)

  def value(number) when is_float(number) do
    decimals =
      cond do
        abs(number) >= 100 -> 0
        abs(number) >= 10 -> 1
        true -> 2
      end

    rounded = Float.round(number, decimals)

    if decimals == 0 or rounded == trunc(rounded) do
      Number.Delimit.number_to_delimited(rounded, precision: 0)
    else
      rounded |> :erlang.float_to_binary(decimals: decimals) |> String.trim_trailing("0")
    end
  end

  @doc "A state's value as a person reads it: `unlocked` is Unlocked."
  @spec state_value(String.t()) :: String.t()
  def state_value(value), do: capitalize(value)

  defp capitalize(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp capitalize(""), do: ""

  @doc """
  The component's latest readings in the order they're shown: those named by
  the conventions first, then the rest, and battery, voltage and signal
  strength last, each by name. Each is `{name, value, at}`.
  """
  @spec readings(DeviceComponent.t()) :: [{String.t(), number(), String.t()}]
  def readings(%DeviceComponent{readings: readings}) do
    readings
    |> Enum.map(fn {name, %{"value" => value, "at" => at}} -> {name, value, at} end)
    |> Enum.sort_by(fn {name, _value, _at} -> {name in @housekeeping, is_nil(unit(name)), name} end)
  end

  @doc "The component's current states, by name. Each is `{name, value, since, detail}`."
  @spec states(DeviceComponent.t()) :: [{String.t(), String.t(), DateTime.t() | nil, String.t() | nil}]
  def states(%DeviceComponent{state: state}) do
    state
    |> Enum.sort()
    |> Enum.map(fn {name, entry} -> {name, entry["value"], parse_time(entry["since"]), entry["detail"]} end)
  end

  defp parse_time(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, parsed, _offset} -> parsed
      _ -> nil
    end
  end

  defp parse_time(_at), do: nil

  @doc "A short span of time: 26 m, 1 h 26 m, 2 d 4 h."
  @spec span(integer()) :: String.t()
  def span(seconds) when seconds < 60, do: "<1 m"
  def span(seconds) when seconds < 3600, do: "#{div(seconds, 60)} m"
  def span(seconds) when seconds < 86_400, do: join_span(div(seconds, 3600), "h", div(rem(seconds, 3600), 60), "m")
  def span(seconds), do: join_span(div(seconds, 86_400), "d", div(rem(seconds, 86_400), 3600), "h")

  defp join_span(big, big_unit, 0, _small_unit), do: "#{big} #{big_unit}"
  defp join_span(big, big_unit, small, small_unit), do: "#{big} #{big_unit} #{small} #{small_unit}"

  defp for_how_long(nil), do: nil
  defp for_how_long(since), do: "for " <> span(max(DateTime.diff(DateTime.utc_now(), since), 0))

  # An icon only where the state's name says what it shows.
  defp state_icon("lock", "locked"), do: "lucide-lock"
  defp state_icon("lock", "unlocked"), do: "lucide-lock-open"
  defp state_icon("door", "open"), do: "lucide-door-open"
  defp state_icon("door", "closed"), do: "lucide-door-closed"
  defp state_icon(_name, _value), do: nil

  ## The list's Reading column

  @doc """
  The list's Reading column: the first state and how long it has held, with
  a reading under it; or, with no state, the first reading and the next two.
  A missing component's last known value is greyed out.
  """
  attr(:component, DeviceComponent, required: true)

  def reading_cell(assigns) do
    assigns =
      assign(assigns,
        missing?: DeviceComponent.status(assigns.component) == :missing,
        states: states(assigns.component),
        readings: readings(assigns.component)
      )

    ~H"""
    <div :if={@states == [] and @readings == []} class="text-xs text-content-faint">—</div>

    <div :if={@states != []} class={["flex min-w-0 flex-col gap-0.5", @missing? && "opacity-60"]}>
      <% {name, value, since, _detail} = hd(@states) %>
      <span class="flex min-w-0 items-baseline gap-1.5">
        <span :if={state_icon(name, value)} class={[state_icon(name, value), "size-3.5 shrink-0 self-center text-content-body"]} aria-hidden="true"></span>
        <span class="truncate text-ui/4 font-medium text-content-strong">{state_value(value)}</span>
        <span :if={!@missing?} class="shrink-0 text-xs text-content-faint">{for_how_long(since)}</span>
        <span :if={@missing?} class="shrink-0 text-xs text-content-faint">when last seen</span>
      </span>
      <span :if={@readings != []} class="truncate font-mono text-xs text-content-muted">
        <.inline_reading reading={hd(@readings)} named />
      </span>
    </div>

    <div :if={@states == [] and @readings != []} class={["flex min-w-0 flex-col gap-0.5", @missing? && "opacity-60"]}>
      <% {name, value, _at} = hd(@readings) %>
      <span class="flex min-w-0 items-baseline gap-1">
        <span class="font-mono text-ui/4 text-content-strong">{value(value)}</span>
        <span class="truncate text-xs text-content-muted">{unit(name) || label(name)}</span>
      </span>
      <span :if={length(@readings) > 1} class="flex min-w-0 items-baseline gap-2 font-mono text-xs text-content-muted">
        <.inline_reading :for={reading <- @readings |> tl() |> Enum.take(2)} reading={reading} />
        <span :if={length(@readings) > 3} class="rounded-xs bg-surface-muted px-1 font-sans text-2xs text-content-muted">
          +{length(@readings) - 3}
        </span>
      </span>
    </div>
    """
  end

  attr(:reading, :any, required: true)
  attr(:named, :boolean, default: false)

  defp inline_reading(assigns) do
    {name, value, _at} = assigns.reading
    assigns = assign(assigns, name: name, value: value)

    ~H"""
    <span class="whitespace-nowrap">
      <span :if={@named} class="mr-1 font-sans">{label(@name)}</span>{value(@value)}<span :if={unit(@name)} class="ml-0.5 font-sans">{unit(@name)}</span><span
        :if={!@named and !unit(@name)}
        class="ml-1 font-sans"
      >{label(@name)}</span>
    </span>
    """
  end

  ## A card's value

  @doc """
  The value on a component's card: its first state, large, with how long it
  has held; or its first reading, large; or, with more than two readings, up
  to six of them in a grid.
  """
  attr(:component, DeviceComponent, required: true)

  def card_value(assigns) do
    assigns =
      assign(assigns,
        missing?: DeviceComponent.status(assigns.component) == :missing,
        states: states(assigns.component),
        readings: readings(assigns.component)
      )

    ~H"""
    <div :if={@states != []} class={["flex min-w-0 items-center gap-2", @missing? && "opacity-60"]}>
      <% {name, value, since, _detail} = hd(@states) %>
      <span :if={state_icon(name, value)} class={[state_icon(name, value), "size-4.5 shrink-0 text-content-strong"]} aria-hidden="true"></span>
      <span class="truncate text-xl/6 font-medium text-content-strong">{state_value(value)}</span>
      <span class="shrink-0 text-xs text-content-muted">{if @missing?, do: "when last seen", else: for_how_long(since)}</span>
      <span :if={@readings != []} class="ml-auto shrink-0 font-mono text-xs text-content-muted">
        <.inline_reading reading={hd(@readings)} named />
      </span>
    </div>

    <div :if={@states == [] and @readings != [] and length(@readings) <= 2} class={["flex min-w-0 items-baseline gap-3", @missing? && "opacity-60"]}>
      <span :for={{name, value, _at} <- @readings} class="flex items-baseline gap-1">
        <span class="font-mono text-figure-sm font-normal text-content-strong">{value(value)}</span>
        <span class="text-xs text-content-muted">{unit(name) || label(name)}</span>
      </span>
    </div>

    <div
      :if={@states == [] and length(@readings) > 2}
      class={["grid grid-cols-3 overflow-clip rounded-card border border-line-subtle", @missing? && "opacity-60"]}
    >
      <div
        :for={{name, value, _at} <- Enum.take(@readings, 6)}
        class="flex min-w-0 flex-col gap-0.5 border-line-subtle px-2.5 py-1.5 not-nth-[3n]:border-r nth-[n+4]:border-t"
      >
        <span class="truncate text-2xs text-content-muted">{label(name)}</span>
        <span class="truncate font-mono text-xs text-content-strong">
          {value(value)}<span :if={unit(name)} class="ml-0.5 font-sans text-content-muted">{unit(name)}</span>
        </span>
      </div>
    </div>
    """
  end

  ## The panel

  @doc """
  The panel's Readings section: a card per reading with its latest value and
  a line over the window `history` covers. `history` is `nil` while it loads.
  """
  attr(:component, DeviceComponent, required: true)
  attr(:history, :any, required: true, doc: "`Components.readings_history/2`'s result, or `nil`")

  def readings_section(assigns) do
    assigns = assign(assigns, :readings, readings(assigns.component))

    ~H"""
    <section :if={@readings != []} id="component-readings" class="border-b border-line-default px-6 py-5 max-sm:px-4">
      <p class="text-label font-medium text-content-muted uppercase">
        Readings · {window_label(@history)}
      </p>
      <div class="mt-3 grid grid-cols-2 gap-2 max-sm:grid-cols-1">
        <div
          :for={{name, value, _at} <- @readings}
          id={"component-reading-#{name}"}
          class="flex min-w-0 flex-col gap-1.5 rounded-card border border-line-default px-3 pt-2.5 pb-2"
        >
          <span class="flex min-w-0 items-baseline gap-1.5">
            <span class="truncate text-xs font-medium text-content-strong">{label(name)}</span>
            <span class="truncate font-mono text-2xs text-content-faint">{name}</span>
          </span>
          <span class="flex items-baseline gap-1">
            <span class="font-mono text-figure-sm font-normal text-content-strong">{value(value)}</span>
            <span :if={unit(name)} class="text-xs text-content-muted">{unit(name)}</span>
          </span>
          <.line points={series(@history, name)} />
        </div>
      </div>
    </section>
    """
  end

  defp window_label(%{window: :fourteen_days}), do: "last 14 days"
  defp window_label(_history), do: "last 6 hours"

  defp series(%{series: series}, name), do: Map.get(series, name)
  defp series(_loading, _name), do: nil

  attr(:points, :any, required: true, doc: "`[{DateTime.t(), number}]`, oldest first, or `nil` while loading")

  # A line over the points' own span, scaled to their own range: the shape
  # of the change, not its size.
  defp line(%{points: nil} = assigns) do
    ~H"""
    <div class="h-6 animate-pulse rounded bg-surface-muted" aria-hidden="true"></div>
    """
  end

  defp line(%{points: points} = assigns) when length(points) < 2 do
    ~H"""
    <div class="flex h-6 items-center text-2xs text-content-faint">Not enough to draw yet</div>
    """
  end

  defp line(assigns) do
    {first, _} = hd(assigns.points)
    {last, _} = List.last(assigns.points)
    span = max(DateTime.diff(last, first), 1)
    {low, high} = assigns.points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    range = if high == low, do: 1, else: high - low

    points =
      Enum.map_join(assigns.points, " ", fn {at, value} ->
        x = Float.round(DateTime.diff(at, first) * 200 / span, 1)
        y = Float.round(22 - (value - low) * 20 / range, 1)
        "#{x},#{y}"
      end)

    assigns = assign(assigns, :polyline, points)

    ~H"""
    <svg viewBox="0 0 200 24" preserveAspectRatio="none" aria-hidden="true" class="h-6 w-full">
      <polyline
        points={@polyline}
        fill="none"
        stroke-width="1.25"
        vector-effect="non-scaling-stroke"
        stroke-linejoin="round"
        class="stroke-content-muted"
      />
    </svg>
    """
  end

  @doc """
  The panel's State section: for each state, what it is now and since when,
  and a timeline of the window with how long each value lasted.
  """
  attr(:component, DeviceComponent, required: true)
  attr(:history, :any, required: true, doc: "`Components.state_history/2`'s result, or `nil` while it loads")
  attr(:from, :any, required: true, doc: "When the window starts")
  attr(:now, :any, required: true, doc: "When it ends")
  attr(:time_zone, :string, required: true)

  def state_section(assigns) do
    assigns = assign(assigns, :states, states(assigns.component))

    ~H"""
    <section :if={@states != []} id="component-state" class="border-b border-line-default px-6 py-5 max-sm:px-4">
      <div class="flex items-baseline justify-between gap-3">
        <p class="text-label font-medium text-content-muted uppercase">State · last 24 hours</p>
        <p class="text-xs text-content-muted">Every change is kept</p>
      </div>
      <div class="mt-3 flex flex-col gap-2">
        <.state_card
          :for={{name, value, since, detail} <- @states}
          name={name}
          value={value}
          since={since}
          detail={detail}
          history={@history && Map.get(@history, name)}
          loading={is_nil(@history)}
          from={@from}
          now={@now}
          time_zone={@time_zone}
        />
      </div>
    </section>
    """
  end

  attr(:name, :string, required: true)
  attr(:value, :string, required: true)
  attr(:since, :any, required: true)
  attr(:detail, :any, required: true)
  attr(:history, :any, required: true)
  attr(:loading, :boolean, required: true)
  attr(:from, :any, required: true)
  attr(:now, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp state_card(assigns) do
    segments = if assigns.loading, do: [], else: segments(assigns)
    totals = totals(segments)
    colors = totals |> Enum.map(&elem(&1, 0)) |> Enum.zip(@segment_colors) |> Map.new()
    changes = if assigns.history, do: length(assigns.history.changes), else: 0

    assigns =
      assign(assigns,
        segments: segments,
        totals: totals,
        colors: colors,
        changes: changes,
        window: max(DateTime.diff(assigns.now, assigns.from), 1)
      )

    ~H"""
    <div id={"component-state-#{@name}"} class="flex flex-col gap-2.5 rounded-card border border-line-default px-3.5 py-3">
      <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <span class="flex items-baseline gap-1.5">
          <span class="text-xs font-medium text-content-strong">{label(@name)}</span>
          <span class="font-mono text-2xs text-content-faint">{@name}</span>
        </span>
        <span :if={!@loading} class="text-xs text-content-muted">
          {@changes} {if @changes == 1, do: "change", else: "changes"}<span
            :for={{value, seconds} <- @totals}
            :if={length(@totals) > 1}
          > · {value} {span(seconds)}</span>
        </span>
      </div>

      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <span :if={state_icon(@name, @value)} class={[state_icon(@name, @value), "size-4.5 shrink-0 self-center text-content-strong"]} aria-hidden="true"></span>
        <span class="text-xl/6 font-semibold text-content-strong">{state_value(@value)}</span>
        <span :if={@since} class="text-xs text-content-muted">
          since {DateTimes.to_local_string(@since, @time_zone, since_format(@since, @time_zone), false)}, {span(max(DateTime.diff(@now, @since), 0))}<span :if={@detail}> · {@detail}</span>
        </span>
      </div>

      <div :if={@loading} class="h-3 animate-pulse rounded-xs bg-surface-muted" aria-hidden="true"></div>
      <div :if={!@loading} class="flex h-3 gap-px overflow-clip rounded-xs bg-surface-muted" aria-hidden="true">
        <div
          :for={segment <- @segments}
          class={["h-full shrink-0", (segment.value && Map.get(@colors, segment.value)) || "bg-transparent"]}
          style={"width: #{Float.round(segment.seconds * 100 / @window, 3)}%"}
          title={segment.value && state_value(segment.value)}
        >
        </div>
      </div>

      <div class="flex justify-between font-mono text-2xs text-content-faint">
        <span :for={at <- axis(@from, @now)}>{DateTimes.to_local_string(at, @time_zone, :time, false)}</span>
        <span>now</span>
      </div>

      <div :if={!@loading and @totals != []} class="flex flex-wrap gap-x-3.5 gap-y-1 text-xs text-content-body">
        <span :for={{value, _seconds} <- @totals} class="flex items-center gap-1.5">
          <span class={["size-2 rounded-xs", Map.get(@colors, value)]} aria-hidden="true"></span>
          {value}
        </span>
      </div>
    </div>
    """
  end

  defp since_format(since, time_zone) do
    if DateTimes.day_label(since, time_zone) == "Today", do: :time, else: :short_datetime
  end

  # Four labels a quarter of the window apart, then "now".
  defp axis(from, now) do
    step = div(DateTime.diff(now, from), 4)
    for quarter <- 0..3, do: DateTime.add(from, quarter * step)
  end

  @doc false
  # The window cut into spans of one value each, oldest first. The value
  # when the window opened is what the history says it was then; failing
  # that, the current value if it was set before the window, and otherwise
  # unknown, drawn as a gap. The current value is added as a change of its
  # own if the history hasn't caught up with it, as it won't have where
  # analytics are off.
  def segments(%{history: history, value: value, since: since, from: from, now: now}) do
    history = history || %{before: nil, changes: []}
    changes = history.changes |> Enum.map(&{to_utc(&1.at), &1.value}) |> with_current(value, since)
    opening = opening(history, changes, value, since, from)

    points =
      [{from, opening} | Enum.map(changes, fn {at, value} -> {latest(at, from), value} end)]

    points
    |> Enum.zip(tl(points) ++ [{now, nil}])
    |> Enum.map(fn {{start, value}, {finish, _next}} ->
      %{value: value, seconds: max(DateTime.diff(finish, start), 0)}
    end)
    |> Enum.reject(&(&1.seconds == 0))
  end

  defp with_current(changes, _value, nil), do: changes

  defp with_current(changes, value, since) do
    case List.last(changes) do
      {_at, ^value} -> changes
      _ -> changes ++ [{since, value}]
    end
  end

  defp opening(%{before: before}, _changes, _value, _since, _from) when is_binary(before), do: before
  defp opening(_history, [], value, _since, _from), do: value

  defp opening(%{changes: []}, _changes, value, %DateTime{} = since, from),
    do: if(DateTime.before?(since, from), do: value)

  defp opening(_history, _changes, _value, _since, _from), do: nil

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_utc(%DateTime{} = at), do: at

  # How long each value lasted, longest first.
  defp totals(segments) do
    segments
    |> Enum.reject(&is_nil(&1.value))
    |> Enum.group_by(& &1.value, & &1.seconds)
    |> Enum.map(fn {value, seconds} -> {value, Enum.sum(seconds)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end
end
