defmodule NervesHubWeb.Components.ErrorReports do
  @moduledoc """
  What a product's errors list and an error's page share: the status badge,
  the short name an error goes by, its top frame, the firmware it was seen on
  and the 14-day sparkline.
  """

  use Phoenix.Component

  alias NervesHub.ErrorReports.ErrorGroup

  @new_for_days 7

  @docs_url "https://github.com/nerves-hub/nerves_hub_web/blob/main/docs/error_reports.md"

  @doc "Where to read about error reports."
  def docs_url(), do: @docs_url

  @doc """
  Which badge an error wears, if any: `:regressed` when a resolved error came
  back, `:new` when it was first seen in the last week, or its status when it
  is resolved or muted. A plain unresolved error wears none.
  """
  @spec badge_kind(ErrorGroup.t()) :: :regressed | :new | :resolved | :muted | nil
  def badge_kind(%ErrorGroup{status: :resolved}), do: :resolved
  def badge_kind(%ErrorGroup{status: :muted}), do: :muted
  def badge_kind(%ErrorGroup{regressed_at: %DateTime{}}), do: :regressed

  def badge_kind(%ErrorGroup{first_seen_at: first_seen_at}) do
    if DateTime.diff(DateTime.utc_now(), first_seen_at, :day) < @new_for_days, do: :new
  end

  @doc "The badge `badge_kind/1` picks, or nothing."
  attr(:group, ErrorGroup, required: true)
  attr(:class, :any, default: nil)

  def issue_badge(assigns) do
    assigns = assign(assigns, :kind, badge_kind(assigns.group))

    ~H"""
    <span
      :if={@kind}
      data-badge={@kind}
      class={[
        "inline-flex shrink-0 items-center rounded-sm px-1.5 py-px text-[10px]/4 font-semibold tracking-[0.06em] uppercase",
        badge_tone(@kind),
        @class
      ]}
    >
      {@kind}
    </span>
    """
  end

  defp badge_tone(:regressed), do: "bg-alert-soft text-alert-content"
  defp badge_tone(:new), do: "bg-notice-soft text-notice-content"
  defp badge_tone(:resolved), do: "bg-success-soft text-success-content"
  defp badge_tone(:muted), do: "bg-base-800 text-content-muted"

  @doc """
  The name an error goes by in a breadcrumb or a toast: the exception in
  `** (MatchError) ...`, or the start of the reason when it isn't shaped
  like one.
  """
  @spec short_name(String.t()) :: String.t()
  def short_name(reason) do
    case Regex.run(~r/^\*\* \(([^)\s]+)\)/, reason, capture: :all_but_first) do
      [name] when is_binary(name) -> name
      _no_match -> truncate(reason, 32)
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  @doc """
  The innermost frame, as the list and the header show it:
  `Module.function · file:line`. `nil` for an error reported without frames.
  """
  @spec top_frame(ErrorGroup.t()) :: String.t() | nil
  def top_frame(%ErrorGroup{top_frame_module: nil}), do: nil

  def top_frame(%ErrorGroup{} = group) do
    call = "#{group.top_frame_module}.#{group.top_frame_function}"

    case group.top_frame_file do
      nil -> call
      file -> "#{call} · #{location(file, group.top_frame_line)}"
    end
  end

  @doc "A file and line, or the file alone when the line is unknown."
  def location(file, nil), do: file
  def location(file, line), do: "#{file}:#{line}"

  @doc """
  What to call the firmware a report was seen on, given the
  `NervesHub.ErrorReports.firmware_by_uuid/2` lookup: its version, or the start
  of its UUID when the product no longer has it. Deleted firmware says so.
  `nil` when the device didn't say.
  """
  @spec firmware_label(String.t() | nil, map()) :: %{text: String.t(), deleted?: boolean()} | nil
  def firmware_label(uuid, _firmware) when uuid in [nil, ""], do: nil

  def firmware_label(uuid, firmware) do
    case Map.fetch(firmware, uuid) do
      {:ok, %{version: version, deleted?: deleted?}} -> %{text: version, deleted?: deleted?}
      :error -> %{text: short_uuid(uuid), deleted?: true}
    end
  end

  defp short_uuid(uuid) when byte_size(uuid) > 8, do: String.slice(uuid, 0, 8) <> "…"
  defp short_uuid(uuid), do: uuid

  @doc "A firmware label, with \"deleted\" after it when the firmware is gone."
  attr(:label, :map, required: true)
  attr(:class, :any, default: nil)

  def firmware(assigns) do
    ~H"""
    <span class={["font-mono", @class]}>{@label.text}<span :if={@label.deleted?} class="font-sans text-content-faint"> deleted</span></span>
    """
  end

  @doc """
  A day-by-day sparkline, drawn on the server. Red when the error is the
  kind that wants attention now (`hot`), grey otherwise.
  """
  attr(:daily, :list, required: true)
  attr(:hot, :boolean, default: false)
  attr(:class, :any, default: nil)

  def sparkline(assigns) do
    max = max(Enum.max(assigns.daily, fn -> 0 end), 1)
    last = max(length(assigns.daily) - 1, 1)

    points =
      assigns.daily
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {count, index} ->
        x = Float.round(index * 120 / last, 1)
        y = Float.round(22 - count * 20 / max, 1)
        "#{x},#{y}"
      end)

    assigns = assign(assigns, points: points, area: "0,24 #{points} 120,24")

    ~H"""
    <svg viewBox="0 0 120 24" preserveAspectRatio="none" aria-hidden="true" class={["h-6 w-30", @class]}>
      <polygon points={@area} class={(@hot && "fill-alert-soft") || "fill-content-faint/10"} />
      <polyline
        points={@points}
        fill="none"
        stroke-width="1.25"
        vector-effect="non-scaling-stroke"
        stroke-linejoin="round"
        class={(@hot && "stroke-alert") || "stroke-content-muted"}
      />
    </svg>
    """
  end

  @doc """
  An error's events over a window, as bars drawn on the server: one per hour
  or day, red when it falls in the error's open period (`hot?`), grey
  otherwise. `markers` are dashed lines at a point in the window, from 0 at
  its start to 1 at its end: `:resolved` grey, `:release` in the notice
  colour.
  """
  attr(:id, :string, required: true)
  attr(:bars, :list, required: true, doc: "`%{count:, hot?:, label:}`, oldest first")
  attr(:markers, :list, default: [], doc: "`%{kind:, x:}`")
  attr(:axis, :list, required: true, doc: "labels spread evenly under the bars")

  def events_chart(assigns) do
    count = max(length(assigns.bars), 1)
    max = assigns.bars |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end) |> max(1)

    bars =
      assigns.bars
      |> Enum.with_index()
      |> Enum.map(fn {bar, index} ->
        height = if bar.count == 0, do: 1.5, else: max(bar.count * 96 / max, 3)
        Map.merge(bar, %{x: index * 10 + 1.5, height: Float.round(height * 1.0, 2)})
      end)

    assigns = assign(assigns, width: count * 10, rendered: bars)

    ~H"""
    <div id={@id} class="flex flex-col gap-2">
      <svg viewBox={"0 0 #{@width} 100"} preserveAspectRatio="none" role="img" aria-label="Events over time" class="h-40 w-full max-sm:h-24">
        <rect
          :for={bar <- @rendered}
          x={bar.x}
          y={100 - bar.height}
          width="7"
          height={bar.height}
          class={[
            (bar.count == 0 && "fill-line-default") || (bar.hot? && "fill-alert") || "fill-base-700"
          ]}
        >
          <title>{bar.label}: {bar.count}</title>
        </rect>
        <line
          :for={marker <- @markers}
          data-marker={marker.kind}
          x1={marker.x * @width}
          x2={marker.x * @width}
          y1="0"
          y2="100"
          stroke-width="1"
          stroke-dasharray={(marker.kind == :release && "2 3") || "4 3"}
          vector-effect="non-scaling-stroke"
          class={(marker.kind == :release && "stroke-notice") || "stroke-content-faint"}
        />
      </svg>
      <div class="flex justify-between border-t border-line-subtle pt-1.5 font-mono text-[11px]/4 text-content-faint">
        <span :for={{label, index} <- Enum.with_index(@axis)} class={index not in [0, length(@axis) - 1] && "max-sm:hidden"}>{label}</span>
      </div>
    </div>
    """
  end

  @doc """
  An occurrence's context, labelled for reading. The vitals the protocol
  names (`uptime_ms`, `reboot_count`, `free_memory_bytes`) get labels and
  units; any other key is shown as the device sent it.
  Returns `[{label, value, known?}]`, the known ones first.
  """
  @spec context_entries(map()) :: [{String.t(), String.t(), boolean()}]
  def context_entries(context) when is_map(context) do
    {known, other} =
      context
      |> Enum.map(fn {key, value} -> context_entry(key, value) end)
      |> Enum.split_with(&elem(&1, 2))

    Enum.sort_by(known, &known_order(elem(&1, 0))) ++ Enum.sort_by(other, &elem(&1, 0))
  end

  def context_entries(_context), do: []

  defp context_entry("reboot_count", value), do: {"Reboots", value, true}
  defp context_entry("uptime_ms", value), do: {"Uptime", format_uptime(value), true}
  defp context_entry("free_memory_bytes", value), do: {"Free memory", format_bytes(value), true}
  defp context_entry(key, value), do: {key, value, false}

  defp known_order("Reboots"), do: 0
  defp known_order("Uptime"), do: 1
  defp known_order(_free_memory), do: 2

  defp format_uptime(value) do
    case Integer.parse(value) do
      {ms, ""} -> duration(div(ms, 1000))
      _ -> value
    end
  end

  defp duration(seconds) when seconds < 60, do: "#{seconds} s"
  defp duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  defp duration(seconds) when seconds < 86_400 do
    "#{div(seconds, 3600)} h #{seconds |> rem(3600) |> div(60)} min"
  end

  defp duration(seconds), do: "#{div(seconds, 86_400)} d #{seconds |> rem(86_400) |> div(3600)} h"

  defp format_bytes(value) do
    case Integer.parse(value) do
      {bytes, ""} -> megabytes(bytes)
      _ -> value
    end
  end

  defp megabytes(bytes) when bytes < 1_000_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  defp megabytes(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  @doc "A byte count for the truncation note: 8 KB, 21 KB, 1.2 MB."
  @spec size_label(non_neg_integer()) :: String.t()
  def size_label(bytes) when bytes < 1_000, do: "#{bytes} bytes"
  def size_label(bytes) when bytes < 1_000_000, do: "#{round(bytes / 1_000)} KB"
  def size_label(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"
end
