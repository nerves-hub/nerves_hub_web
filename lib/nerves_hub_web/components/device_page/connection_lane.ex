defmodule NervesHubWeb.Components.DevicePage.ConnectionLane do
  @moduledoc """
  The connection lane at the top of the Health tab's History card, drawn from a
  `NervesHub.Devices.ConnectionTimeline` over the span the charts show.

  It shows when the device was online, when it was offline and why, and where
  it reconnected without being gone long enough to count as offline, over the
  time frame or the zoom. On a pointer, hovering an offline span shows what
  happened in a tooltip; a phone has no hover, so tapping one opens the same
  detail under the lane. Either way the `ConnectionLane` hook darkens the
  charts' matching Offline bands while it's open.
  """

  use NervesHubWeb, :component
  use Gettext, backend: NervesHubWeb.Gettext

  alias NervesHub.Devices.ConnectionTimeline
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Helpers.Timezone

  # The spacing between the labels under the lane, in minutes. The first that
  # leaves room for every label is used: half-hours across three hours, every
  # four hours across a day, days across a week, as the charts' axes have them.
  @label_steps [5, 10, 15, 30, 60, 120, 240, 360, 720, 1440, 2880]
  @most_labels 7

  # Where a tooltip would run off the lane's right edge, it hangs left from
  # the end of its span instead.
  @tooltip_flip_percent 70

  attr(:id, :string, required: true)
  attr(:timeline, ConnectionTimeline, required: true)
  attr(:from, DateTime, required: true)
  attr(:until, DateTime, required: true)
  attr(:time_zone, :string, required: true)
  attr(:now, DateTime, default: nil, doc: "when the timeline was read, for how long an open span has lasted")

  def lane(assigns) do
    %{timeline: timeline, from: from, until: until} = assigns

    assigns =
      assign(assigns,
        now: assigns.now || until,
        summary: ConnectionTimeline.summary(timeline, from, until),
        segments: segments(timeline, from, until),
        ticks: for(at <- timeline.reconnects, inside?(at, from, until), do: position(at, from, until)),
        labels: labels(from, until, assigns.time_zone)
      )

    ~H"""
    <div id={@id} phx-hook="ConnectionLane" class="relative flex flex-col gap-2 border-t border-line-subtle px-4 pt-3.5 pb-3 max-sm:gap-1.5 max-sm:py-3">
      <div class="flex h-5 shrink-0 items-center justify-between gap-3">
        <div class="flex min-w-0 items-baseline gap-2.5">
          <h3 class="text-ui/5 font-medium text-content-strong max-sm:text-sm/4.5">Connection</h3>
          <p class="truncate text-xs text-content-muted max-sm:hidden">
            Online <span class="font-medium text-content-strong">{@summary.online_percent}%</span> of this period · <span class="font-medium text-content-strong">{@summary.disconnects}</span>
            {ngettext("disconnect", "disconnects", @summary.disconnects)} · <span class="font-medium text-content-strong">{@summary.reconnects}</span>
            {ngettext("reconnect", "reconnects", @summary.reconnects)}
          </p>
        </div>
        <span class="text-sm/4.5 font-medium text-content-strong sm:hidden">{@summary.online_percent}% online</span>
        <div class="flex shrink-0 items-center gap-3.5 max-sm:hidden" aria-hidden="true">
          <span class="flex items-center gap-1.5 text-xs text-content-muted">
            <span class="size-2.5 shrink-0 rounded-xs bg-status-online"></span> Online
          </span>
          <span class="flex items-center gap-1.5 text-xs text-content-muted">
            <span class="size-2.5 shrink-0 rounded-xs inset-ring inset-ring-offline-edge offline-hatch"></span> Offline
          </span>
          <span class="flex items-center gap-1.5 text-xs text-content-muted">
            <span class="h-3.5 w-[1.5px] shrink-0 bg-reconnect-tick"></span> Reconnected
          </span>
        </div>
      </div>

      <div class="relative h-10 shrink-0">
        <div class="absolute inset-x-0 top-1.5 h-3 max-sm:h-3.5">
          <%= for segment <- @segments do %>
            <div :if={segment.kind == :online} class="absolute inset-y-0 rounded-xs bg-status-online" style={span_style(segment)}></div>
            <div :if={segment.kind == :offline} class="group/offline absolute inset-y-0" style={span_style(segment)}>
              <button
                type="button"
                data-offline-span={segment.key}
                data-from={segment.from_ms}
                data-until={segment.until_ms}
                aria-pressed="false"
                aria-label={"#{offline_for(segment.span, @now)}, #{time_span(segment.span, @time_zone)}"}
                class="absolute inset-0 cursor-pointer border border-offline-edge offline-hatch aria-pressed:border-[1.5px] aria-pressed:border-content-strong"
              ></button>
              <div
                role="tooltip"
                class={[
                  "pointer-events-none invisible absolute top-full z-10 mt-1 flex w-59 flex-col gap-0.5 rounded-sm border border-line-default bg-surface-overlay px-2.5 py-2 shadow-overlay group-focus-within/offline:visible group-hover/offline:visible max-sm:hidden",
                  tooltip_side(segment)
                ]}
              >
                <span class="text-xs text-content-muted">{time_span(segment.span, @time_zone)}</span>
                <span class="text-ui/4.5 font-semibold text-content-strong">{offline_for(segment.span, @now)}</span>
                <span :if={reason(segment.span.reason)} class="text-xs text-content-muted">{reason(segment.span.reason)}</span>
                <span class="text-xs text-content-faint">{came_back(segment.span)}</span>
              </div>
            </div>
          <% end %>
          <span
            :for={left <- @ticks}
            class="absolute -inset-y-1 w-[1.5px] -translate-x-1/2 bg-reconnect-tick shadow-[0_0_0_1px_var(--color-surface-raised)]"
            style={"left: #{left}%"}
            aria-hidden="true"
          ></span>
        </div>
        <div class="absolute inset-x-0 bottom-0 h-4" aria-hidden="true">
          <span
            :for={{label, index} <- Enum.with_index(@labels)}
            class={["absolute -translate-x-1/2 text-2xs/4 whitespace-nowrap text-content-faint", rem(index, 2) == 1 && "max-sm:hidden"]}
            style={"left: #{label.left}%"}
          >
            {label.text}
          </span>
        </div>
      </div>

      <div
        :for={segment <- @segments}
        :if={segment.kind == :offline}
        data-offline-detail={segment.key}
        class="flex flex-col gap-0.5 rounded-sm bg-surface-muted px-3 py-2.5 sm:hidden"
        style="display: none"
      >
        <div class="flex items-baseline justify-between gap-3">
          <span class="text-ui/4.5 font-semibold text-content-strong">{offline_for(segment.span, @now)}</span>
          <span class="text-xs text-content-muted">{time_span(segment.span, @time_zone, :time)}</span>
        </div>
        <span class="text-xs text-content-muted">
          {detail_line(segment.span)}
        </span>
      </div>
    </div>
    """
  end

  # Where the device came back: "Came back on Wi-Fi · 10.0.4.17". A phone has
  # room for the interface only.
  defp came_back(span, with_address? \\ true)

  defp came_back(%{until: nil}, _with_address?), do: "Hasn't come back yet"

  defp came_back(span, with_address?) do
    case {interface(span.interface), if(with_address?, do: span.ip_address)} do
      {nil, nil} -> "Came back"
      {interface, nil} -> "Came back on #{interface}"
      {nil, ip_address} -> "Came back from #{ip_address}"
      {interface, ip_address} -> "Came back on #{interface} · #{ip_address}"
    end
  end

  defp interface("wifi"), do: "Wi-Fi"
  defp interface("ethernet"), do: "Ethernet"
  defp interface("cellular"), do: "cellular"
  defp interface(_unknown), do: nil

  defp lowercase_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest

  # The phone's line under the tapped span: "Stopped sending heartbeats · came
  # back on Wi-Fi", or only where it came back when no reason is known.
  defp detail_line(span) do
    case reason(span.reason) do
      nil -> came_back(span, false)
      reason -> "#{reason} · #{lowercase_first(came_back(span, false))}"
    end
  end

  @doc """
  Why a connection ended, as `disconnected_reason` records it, in words. Nil
  when no connection is known before the time offline, so there's no reason
  to give.
  """
  @spec reason(String.t() | nil) :: String.t() | nil
  def reason(nil), do: nil
  def reason("Stale connection"), do: "Stopped sending heartbeats"
  def reason("Reconnected"), do: "Dropped without closing the connection"
  def reason(""), do: "Closed the connection"
  def reason(other), do: other

  # The lane in order: online stretches between the offline spans, each with
  # where it sits as a percentage of the span shown.
  defp segments(timeline, from, until) do
    offline =
      for span <- timeline.offline,
          {start, stop} <- [ConnectionTimeline.clip(span, from, until)],
          DateTime.before?(start, stop) do
        %{
          kind: :offline,
          key: "#{DateTime.to_unix(span.from, :millisecond)}",
          span: span,
          start: start,
          stop: stop,
          from_ms: DateTime.to_unix(start, :millisecond),
          until_ms: DateTime.to_unix(stop, :millisecond)
        }
      end

    {online, covered_to} =
      Enum.flat_map_reduce(offline, from, fn %{start: start, stop: stop}, covered_to ->
        {online(covered_to, start), stop}
      end)

    (offline ++ online ++ online(covered_to, until))
    |> Enum.sort_by(& &1.start, DateTime)
    |> Enum.map(fn segment ->
      Map.merge(segment, %{
        left: position(segment.start, from, until),
        width: width(segment.start, segment.stop, from, until)
      })
    end)
  end

  defp online(start, stop) do
    if DateTime.before?(start, stop), do: [%{kind: :online, start: start, stop: stop}], else: []
  end

  defp position(at, from, until) do
    Float.round(DateTime.diff(at, from, :millisecond) * 100 / total(from, until), 3)
  end

  defp width(start, stop, from, until) do
    Float.round(DateTime.diff(stop, start, :millisecond) * 100 / total(from, until), 3)
  end

  defp total(from, until), do: max(DateTime.diff(until, from, :millisecond), 1)

  defp tooltip_side(%{left: left}) when left >= @tooltip_flip_percent, do: "right-0"
  defp tooltip_side(_segment), do: "left-0"

  defp span_style(segment), do: "left: #{segment.left}%; width: #{segment.width}%"

  defp inside?(at, from, until), do: DateTime.after?(at, from) and DateTime.before?(at, until)

  # "Nov 6, 12:20 PM – 12:34 PM", or "Since Nov 6, 12:20 PM" for a span the
  # device hasn't come back from.
  defp time_span(span, time_zone, first_format \\ :short_datetime)

  defp time_span(%{from: from, until: nil}, time_zone, first_format) do
    "Since #{DateTimes.to_local_string(from, time_zone, first_format, false)}"
  end

  defp time_span(%{from: from, until: until}, time_zone, first_format) do
    until_format =
      if DateTimes.day_key(from, time_zone) == DateTimes.day_key(until, time_zone), do: :time, else: :short_datetime

    "#{DateTimes.to_local_string(from, time_zone, first_format, false)} – #{DateTimes.to_local_string(until, time_zone, until_format, false)}"
  end

  defp offline_for(%{from: from, until: until}, now) do
    "Offline for #{duration(DateTime.diff(until || now, from))}"
  end

  @doc """
  A length of time the way the lane says it: "14 min", "2 hr 5 min", "3 days 4 hr".
  """
  @spec duration(integer()) :: String.t()
  def duration(seconds) when seconds < 3600, do: "#{max(div(seconds, 60), 1)} min"

  def duration(seconds) when seconds < 86_400 do
    case {div(seconds, 3600), div(rem(seconds, 3600), 60)} do
      {hours, 0} -> "#{hours} hr"
      {hours, minutes} -> "#{hours} hr #{minutes} min"
    end
  end

  def duration(seconds) do
    days = ngettext("1 day", "%{count} days", div(seconds, 86_400))

    case div(rem(seconds, 86_400), 3600) do
      0 -> days
      hours -> "#{days} #{hours} hr"
    end
  end

  # The times along the bottom of the lane, on round times in the viewer's
  # zone: 11:30 AM and 12:00 PM, rather than 11:17 AM and 11:47 AM.
  defp labels(from, until, time_zone) do
    minutes = div(DateTime.diff(until, from), 60)
    step = Enum.find(@label_steps, List.last(@label_steps), &(div(minutes, &1) <= @most_labels))
    format = if step >= 1440, do: :short_date, else: :time
    zone = Timezone.resolve(time_zone)

    from
    |> first_label(step, zone)
    |> Stream.iterate(&next_label(&1, step, zone))
    |> Stream.take_while(&(not DateTime.after?(&1, until)))
    |> Stream.take(@most_labels + 1)
    |> Enum.map(fn at ->
      %{left: position(at, from, until), text: DateTimes.to_local_string(at, time_zone, format, false)}
    end)
    |> Enum.filter(&(&1.left >= 3 and &1.left <= 97))
  end

  # The first round time at or after `from`, counted on the local clock.
  defp first_label(from, step, zone) when step >= 1440 do
    local = DateTime.shift_zone!(from, zone)
    midnight(Date.add(DateTime.to_date(local), 1), zone)
  end

  defp first_label(from, step, zone) do
    local = DateTime.shift_zone!(from, zone)
    minute_of_day = local.hour * 60 + local.minute
    minutes_on = step - rem(minute_of_day, step)

    local
    |> Map.merge(%{second: 0, microsecond: {0, 0}})
    |> DateTime.add(minutes_on, :minute)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp next_label(at, step, zone) when step >= 1440 do
    local = DateTime.shift_zone!(at, zone)
    midnight(Date.add(DateTime.to_date(local), div(step, 1440)), zone)
  end

  defp next_label(at, step, _zone), do: DateTime.add(at, step, :minute)

  defp midnight(date, zone) do
    case DateTime.new(date, ~T[00:00:00], zone) do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
    end
  end
end
