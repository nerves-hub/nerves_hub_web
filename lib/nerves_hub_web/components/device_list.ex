defmodule NervesHubWeb.Components.DeviceList do
  @moduledoc """
  The pieces of a product's devices list (`NervesHubWeb.Live.Devices.Index`).

  The state and reason tabs, the table's cells and the Needs attention rows,
  the pager, the no-match and past-last-page states, and the first-load
  skeletons. The cells keep to one rule: only what needs someone's attention
  gets colour, so a healthy device reads as plain grey text and an unhealthy
  one as a red chip.
  """
  use NervesHubWeb, :component

  import Number.Delimit, only: [number_to_delimited: 2]

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHub.Devices.Updates
  alias NervesHubWeb.Components.DeviceSleep
  alias NervesHubWeb.Components.Fleet
  alias NervesHubWeb.Components.HealthStatus
  alias NervesHubWeb.Components.Sorting
  alias Phoenix.LiveView.JS

  # Not seen for this long, a device needs attention: the cut-off in
  # `DeviceFiltering.reason_dynamic("not_seen")`.
  @not_seen_days DeviceFiltering.not_seen_days()

  @tabs [
    %{state: "", label: "All", dot: nil},
    %{state: "online", label: "Online", dot: "bg-status-online"},
    %{state: "attention", label: "Needs attention", dot: "bg-alert"},
    %{state: "updating", label: "Updating", dot: "bg-primary"},
    %{state: "offline", label: "Offline", dot: "bg-status-offline"}
  ]

  @doc "The state tabs, in the order they're shown. `state` \"\" is All."
  @spec tabs() :: [%{state: String.t(), label: String.t(), dot: String.t() | nil}, ...]
  def tabs(), do: @tabs

  attr(:tabs, :list, required: true, doc: "`tabs/0`, each with its `:path`")
  attr(:selected, :string, required: true, doc: "the selected tab's state")
  attr(:counts, :map, default: nil, doc: "`Devices.state_counts/3`, or nil while they load")
  attr(:loading, :boolean, default: false, doc: "the counts are for results that are being replaced")
  attr(:class, :any, default: nil)

  @doc """
  The tabs above the list: All, Online, Needs attention, Updating, Offline.

  While the counts load, or are being replaced (`loading`), each shows a
  placeholder in place of its count rather than a number that's about to
  change.
  """
  def state_tabs(assigns) do
    ~H"""
    <nav
      id="state-tabs"
      aria-label="Device states"
      class={["scrollbar-none flex h-13 shrink-0 items-end gap-6 overflow-x-auto border-b border-line-default px-6 max-sm:h-11 max-sm:gap-5 max-sm:px-4", @class]}
    >
      <.link
        :for={tab <- @tabs}
        id={"state-tab-#{if tab.state == "", do: "all", else: tab.state}"}
        patch={tab.path}
        aria-current={tab.state == @selected && "page"}
        class={[
          "-mb-px flex shrink-0 items-center gap-2 border-b-2 pb-3 text-sm/5 max-sm:gap-1.5 max-sm:pb-2.5",
          if(tab.state == @selected,
            do: "border-primary font-semibold text-content-strong",
            else: "border-transparent text-content-body hover:text-content-strong"
          )
        ]}
      >
        <.status_dot :if={tab.dot} class={["size-1.5", tab.dot]} />
        <span>{tab.label}</span>
        <span :if={@loading or is_nil(@counts)} data-count-pending class="inline-block h-1.5 w-5 animate-pulse rounded-full bg-base-800 motion-reduce:animate-none" aria-hidden="true"></span>
        <span :if={not @loading and not is_nil(@counts)} class={["font-mono text-xs font-normal", tab_count_colour(tab, @counts)]}>
          {tab_count(tab, @counts)}
        </span>
      </.link>
    </nav>
    """
  end

  defp tab_count(%{state: ""}, counts), do: delimited(counts["all"])
  defp tab_count(%{state: state}, counts), do: delimited(counts[state])

  defp tab_count_colour(%{state: "attention"}, %{"attention" => count}) when count > 0, do: "text-alert-content"
  defp tab_count_colour(_tab, _counts), do: "text-content-muted"

  @reason_tabs [
    %{reason: "", label: "All"},
    %{reason: "unhealthy", label: "Unhealthy"},
    %{reason: "failing", label: "Update failing"},
    %{reason: "not_seen", label: "Not seen #{@not_seen_days} d+"}
  ]

  @doc "The Needs attention tab's reasons, in the order shown. `reason` \"\" is All."
  @spec reason_tabs() :: [%{reason: String.t(), label: String.t()}, ...]
  def reason_tabs(), do: @reason_tabs

  attr(:tabs, :list, required: true, doc: "`reason_tabs/0`, each with its `:path`")
  attr(:selected, :string, required: true, doc: "the selected reason")
  attr(:counts, :map, default: nil, doc: "`Devices.state_counts/3`, or nil while they load")

  @doc """
  The Needs attention tab's reasons, a segmented control above its list, or a
  row of pills that scrolls sideways on a phone.
  """
  def reason_tabs(assigns) do
    ~H"""
    <nav
      id="reason-tabs"
      aria-label="Why devices need attention"
      class="flex w-fit max-w-full overflow-x-auto rounded border border-line-control bg-surface-raised max-sm:scrollbar-none max-sm:w-full max-sm:gap-1.5 max-sm:rounded-none max-sm:border-0 max-sm:bg-transparent max-sm:px-4"
    >
      <.link
        :for={tab <- @tabs}
        id={"reason-tab-#{if tab.reason == "", do: "all", else: tab.reason}"}
        patch={tab.path}
        aria-current={tab.reason == @selected && "page"}
        class={[
          "flex h-7 shrink-0 items-center gap-1.5 border-r border-line-control px-2.5 text-xs/4 last:border-r-0",
          "max-sm:h-8 max-sm:rounded-full max-sm:border max-sm:px-3 max-sm:text-ui/4 max-sm:last:border-r",
          if(tab.reason == @selected,
            do: "bg-surface-muted font-medium text-content-strong max-sm:border-content-strong max-sm:bg-content-strong max-sm:text-surface-raised",
            else: "text-content-body hover:bg-surface-muted/60 hover:text-content-strong max-sm:bg-surface-raised"
          )
        ]}
      >
        {tab.label}
        <span class={["font-mono font-normal", if(tab.reason == @selected, do: "text-content-muted max-sm:text-surface-raised/70", else: "text-content-muted")]}>
          {reason_count(tab, @counts)}
        </span>
      </.link>
    </nav>
    """
  end

  defp reason_count(_tab, nil), do: "—"
  defp reason_count(%{reason: ""}, counts), do: delimited(counts["attention"])
  defp reason_count(%{reason: reason}, counts), do: delimited(counts[reason])

  attr(:class, :any, default: nil)

  @doc """
  An empty page of a list that has devices: one past the last page, from an
  old link or after the last page's devices moved away. Links back to the first.
  """
  def past_last_page(assigns) do
    ~H"""
    <div id="past-last-page" class={["flex flex-col items-center rounded-card border border-dashed border-line-default px-6 pt-16 pb-18 text-center", @class]}>
      <p class="text-card-title text-content-strong">Nothing on this page</p>
      <p class="mt-1 max-w-md text-ui/5 text-content-muted">The list has fewer pages than this now.</p>
      <.button id="past-last-page-first" size="sm" class="mt-4" phx-click="paginate" phx-value-page="1">Go to the first page</.button>
    </div>
    """
  end

  attr(:removable, :integer, required: true, doc: "how many filters, and the query, are narrowing the list")

  attr(:suggestions, :list,
    default: nil,
    doc: """
    What removing each would bring back, most first: `%{key, text, count}`,
    where `key` is a filter or `:advanced_query`. Nil while they're counted.
    """
  )

  attr(:can_reset, :boolean, default: false, doc: "whether any of them is a Filters panel filter")
  attr(:search_only, :boolean, default: false, doc: "whether the query is all that's narrowing the list")
  attr(:class, :any, default: nil)

  @doc """
  What the list shows when its filters, or its query, match nothing: what
  removing each of them would bring back, as a button that removes it.
  """
  def no_matches(assigns) do
    assigns = assign(assigns, :helpful, Enum.filter(assigns.suggestions || [], &(&1.count > 0)))

    ~H"""
    <div id="no-matches" class={["flex flex-col items-center rounded-card border border-dashed border-line-default px-6 pt-16 pb-18 text-center", @class]}>
      <span class="mb-4 flex size-9 items-center justify-center rounded-full bg-surface-muted">
        <span class="lucide-search-x size-4 text-content-muted" aria-hidden="true"></span>
      </span>
      <p class="text-card-title text-content-strong">
        {if @search_only, do: "No devices match this search", else: no_matches_title(@removable)}
      </p>
      <p :if={@suggestions} class="mt-1 max-w-md text-ui/5 text-content-muted">
        {no_matches_detail(@removable, @helpful)}
      </p>
      <div :if={@helpful != [] or @can_reset} class="mt-4 flex flex-wrap items-center justify-center gap-2">
        <.button
          :for={suggestion <- Enum.take(@helpful, 3)}
          id={"no-matches-remove-#{suggestion.key}"}
          size="sm"
          phx-click={remove_event(suggestion.key)}
          phx-value-key={suggestion.key != :advanced_query && suggestion.key}
        >
          {if suggestion.key == :advanced_query, do: "Clear", else: "Remove"}
          <span class="font-mono">{suggestion.text}</span>
          <span class="font-mono font-normal text-content-muted">{delimited(suggestion.count)}</span>
        </.button>
        <button
          :if={@can_reset}
          id="no-matches-reset"
          type="button"
          phx-click="reset-filters"
          class="ml-2 cursor-pointer text-ui/4 text-content-body underline decoration-line-strong underline-offset-3 hover:text-content-strong"
        >
          Clear filters
        </button>
      </div>
    </div>
    """
  end

  defp remove_event(:advanced_query), do: "clear-advanced-query"
  defp remove_event(_key), do: "remove-filter"

  defp no_matches_title(1), do: "No devices match this filter"
  defp no_matches_title(2), do: "No devices match both filters"
  defp no_matches_title(_count), do: "No devices match these filters"

  defp no_matches_detail(1, [%{count: count}]), do: "Without it, #{delimited(count)} #{devices(count)} would show here."
  defp no_matches_detail(1, []), do: "Nothing would show here without it either."
  defp no_matches_detail(_removable, []), do: "Nothing would match with any one of them removed either."
  defp no_matches_detail(_removable, _helpful), do: "Removing one of them would bring devices back."

  defp devices(1), do: "device"
  defp devices(_count), do: "devices"

  @typedoc "Why a device needs attention, from `attention_reason/2`."
  @type attention_reason ::
          {:failing, String.t() | nil, pos_integer()}
          | {:unhealthy, String.t()}
          | {:not_seen, DateTime.t() | nil}
          | nil

  @doc """
  Why a device needs attention, by the Needs attention tab's own rules
  (`DeviceFiltering.reason_dynamic/1`): updates on hold after repeated
  failures, then unhealthy, then not seen in #{@not_seen_days} days. A not
  seen reason has no time when the device's last connection is older than
  any connection record (`Connections.last_seen_unrecorded?/2`).

  A device can need attention for more than one reason; `prefer` is the
  reason the list is filtered to, which comes first when the device has it.
  nil is a device that needs no attention.
  """
  @spec attention_reason(Device.t(), String.t()) :: attention_reason()
  def attention_reason(device, prefer \\ "") do
    found = Enum.flat_map(["failing", "unhealthy", "not_seen"], &List.wrap(reason_for(&1, device)))
    Enum.find(found, List.first(found), &(reason_key(&1) == prefer))
  end

  defp reason_for(
         "failing",
         %Device{consecutive_failed_updates: failures, updates_blocked_until: %DateTime{} = until} = device
       )
       when failures > 0 do
    if DateTime.after?(until, DateTime.utc_now()), do: {:failing, release_version(device), failures}
  end

  defp reason_for("unhealthy", %Device{latest_health: %{status: :unhealthy} = health}),
    do: {:unhealthy, health_summary(health)}

  defp reason_for("not_seen", %Device{latest_connection: %{last_seen_at: %DateTime{} = seen}}) do
    if DateTime.diff(DateTime.utc_now(), seen) >= not_seen_seconds(), do: {:not_seen, seen}
  end

  defp reason_for("not_seen", %Device{latest_connection: connection} = device) do
    if Connections.last_seen_unrecorded?(device, connection), do: {:not_seen, nil}
  end

  defp reason_for(_reason, _device), do: nil

  defp reason_key({:failing, _, _}), do: "failing"
  defp reason_key({:unhealthy, _}), do: "unhealthy"
  defp reason_key({:not_seen, _}), do: "not_seen"

  defp release_version(%Device{deployment_group: %{current_release: %{firmware: %{version: version}}}}), do: version
  defp release_version(_device), do: nil

  @doc """
  What put a device's health at its status, short enough for a list row:
  "memory at 94%", or "memory at 94%, +1 more" when more than one metric did.
  """
  @spec health_summary(map()) :: String.t()
  def health_summary(%{status: status, status_reasons: %{} = all_reasons}) do
    case all_reasons[to_string(status)] do
      %{} = reasons when map_size(reasons) > 0 ->
        [{key, reason} | rest] = Enum.sort(reasons)
        summary = metric_summary(key, reason)

        if rest == [], do: summary, else: "#{summary}, +#{length(rest)} more"

      _ ->
        "the device didn't say why"
    end
  end

  def health_summary(_health), do: "the device didn't say why"

  # "memory at 94%", or "memory over 90%" for a reason judged on the share of
  # a window spent over the threshold, whose value is that share.
  defp metric_summary(key, reason) do
    {name, unit} = metric_name(key)

    case reason do
      %{"aggregation" => "share", "threshold" => threshold} -> "#{name} over #{format_number(threshold)}#{unit}"
      %{"value" => value} -> "#{name} at #{format_number(value)}#{unit}"
      _ -> name
    end
  end

  defp metric_name("mem_used_percent"), do: {"memory", "%"}
  defp metric_name("cpu_usage_percent"), do: {"CPU", "%"}
  defp metric_name("cpu_temp"), do: {"temperature", " °C"}
  defp metric_name("disk_used_percentage"), do: {"disk", "%"}

  defp metric_name(key) do
    parts = key |> String.split("_") |> Enum.reject(&(&1 == "usage"))

    if List.last(parts) in ["percent", "percentage"],
      do: {Enum.join(Enum.drop(parts, -1), " "), "%"},
      else: {Enum.join(parts, " "), ""}
  end

  @doc "A metric's value: a float to one decimal place under 10, and none from 10 up."
  @spec format_number(number()) :: String.t()
  def format_number(value) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: if(value >= 10, do: 0, else: 1))

  def format_number(value), do: to_string(value)

  attr(:device, Device, required: true)

  attr(:status, :string,
    default: nil,
    doc:
      ~s("online", "offline", or "asleep" or "overdue" for a device that said it was going to sleep, as the page tracks it)
  )

  attr(:reason, :string, default: "", doc: "the reason the list is filtered to, shown first")
  attr(:peeked, :boolean, default: false)
  attr(:path, :string, required: true, doc: "the device's page")

  @doc """
  A row of the Needs attention list: the device and why it needs attention.
  Clicking it opens the peek; the identifier links to the device.
  """
  def attention_row(assigns) do
    assigns = assign(assigns, :why, attention_reason(assigns.device, assigns.reason))

    ~H"""
    <li
      id={"device-row-#{@device.id}"}
      phx-click={JS.push("peek", value: %{id: @device.id})}
      data-peeked={@peeked}
      class={[
        "flex h-15 cursor-pointer scroll-mt-2 items-center gap-3 border-b border-line-subtle pr-5 last:border-b-0",
        "max-sm:h-auto max-sm:items-start max-sm:gap-2 max-sm:rounded-card max-sm:border max-sm:border-line-default max-sm:bg-surface-raised max-sm:p-3 max-sm:last:border-b",
        if(@peeked, do: "border-l-2 border-l-primary bg-primary/6 pl-3.5", else: "pl-4 hover:bg-primary/4")
      ]}
    >
      <DeviceSleep.status_mark status={@status} connection={@device.latest_connection} class="max-sm:mt-1.75" />
      <div class="flex min-w-0 grow flex-col gap-0.75 max-sm:gap-1.5">
        <.link
          navigate={@path}
          phx-click={%JS{}}
          class={[
            "w-fit max-w-full truncate font-mono text-ui/4 text-content-strong hover:text-primary hover:underline hover:decoration-primary/40",
            "max-sm:text-sm/4.5 max-sm:font-medium max-sm:underline max-sm:decoration-line-strong max-sm:underline-offset-3",
            @peeked && "font-semibold"
          ]}
        >
          {@device.identifier}
        </.link>
        <.why_line why={@why} />
        <%!-- A phone shows no peek beside the list, so the card carries a
              little more: the firmware it runs and its tags. --%>
        <p :if={@device.firmware_metadata || @device.tags not in [nil, []]} class="truncate text-xs/4 text-content-muted sm:hidden">
          <span :if={@device.firmware_metadata} class="font-mono text-content-body">{@device.firmware_metadata.version}</span>
          <span :if={@device.firmware_metadata && @device.tags not in [nil, []]} class="text-content-faint" aria-hidden="true">·</span>
          <span :if={@device.tags not in [nil, []]}>{Enum.join(@device.tags, ", ")}</span>
        </p>
      </div>
    </li>
    """
  end

  attr(:why, :any, required: true)

  defp why_line(%{why: {:failing, version, failures}} = assigns) do
    assigns = assign(assigns, version: version, failures: failures)

    ~H"""
    <span class="truncate text-xs/4 text-alert-content max-sm:text-ui/4 max-sm:font-medium max-sm:whitespace-normal">
      Update<span :if={@version}> to <span class="font-mono">{@version}</span></span> failed {if @failures == 1, do: "once", else: "#{@failures} times"}
    </span>
    """
  end

  defp why_line(%{why: {:unhealthy, summary}} = assigns) do
    assigns = assign(assigns, :summary, summary)

    ~H"""
    <span class="truncate text-xs/4 text-alert-content max-sm:text-ui/4 max-sm:font-medium max-sm:whitespace-normal">Unhealthy · {@summary}</span>
    """
  end

  defp why_line(%{why: {:not_seen, nil}} = assigns) do
    ~H"""
    <span class="truncate text-xs/4 text-content-muted max-sm:text-ui/4 max-sm:whitespace-normal">Last seen unknown</span>
    """
  end

  defp why_line(%{why: {:not_seen, seen}} = assigns) do
    assigns = assign(assigns, :seen, seen)

    ~H"""
    <span class="truncate text-xs/4 text-content-muted max-sm:text-ui/4 max-sm:whitespace-normal">Not seen in {Fleet.duration(DateTime.diff(DateTime.utc_now(), @seen))}</span>
    """
  end

  defp why_line(assigns) do
    ~H"""
    <span class="truncate text-xs/4 text-content-faint">Nothing needs attention now</span>
    """
  end

  attr(:device_id, :integer, required: true)
  attr(:health, :map, default: nil, doc: "the device's latest health, or nil if it has never reported one")

  @doc """
  The device's health. Warning and unhealthy are chips, with the reasons on
  hover; healthy and unknown are plain text.
  """
  def health(%{health: %{status: status}} = assigns) when status in [:warning, :unhealthy] do
    ~H"""
    <.badge
      id={"health-#{@device_id}"}
      tone={if @health.status == :unhealthy, do: "alert", else: "warning"}
      dot
      title={Enum.join(HealthStatus.reason_lines(@health), "\n")}
    >
      {if @health.status == :unhealthy, do: "Unhealthy", else: "Warning"}
    </.badge>
    """
  end

  def health(%{health: %{status: :healthy}} = assigns) do
    ~H"""
    <span id={"health-#{@device_id}"} class="inline-flex items-center gap-1.25 text-xs text-content-muted max-sm:hidden">
      <.status_dot class="size-1.5 bg-success" />Healthy
    </span>
    """
  end

  def health(assigns) do
    ~H"""
    <span id={"health-#{@device_id}"} class="inline-flex items-center gap-1.25 text-xs text-content-faint max-sm:hidden" title={HealthStatus.no_reasons(@health)}>
      <.status_dot class="size-1.5 bg-content-faint/60" />Unknown
    </span>
    """
  end

  @typedoc "What the Firmware column says about a device's updates, from `update_state/3`."
  @type update_state ::
          nil
          | :up_to_date
          | :updates_off
          | :group_paused
          | {:updating, %{stage: String.t(), percent: non_neg_integer()}, String.t() | nil}
          | {:waiting, String.t()}
          | {:blocked, DateTime.t()}
          | {:failing, String.t(), pos_integer()}

  @doc """
  Where a device stands on its updates, for the Firmware column: installing
  one now, or else where it stands against its deployment group's release
  (`Updates.update_status/3`).

  `progress` is the update in progress the page is tracking, if any. The
  device must have its deployment group's current release and firmware
  loaded, as `Devices.filter/3` does. nil is nothing worth saying: a device
  with no group, or that hasn't reported its firmware.
  """
  @spec update_state(Device.t(), map() | nil, DateTime.t()) :: update_state()
  def update_state(device, progress, now \\ DateTime.utc_now())

  def update_state(device, %{} = progress, _now), do: {:updating, progress, inflight_version(device)}

  def update_state(%Device{deployment_group: %{current_release: %{firmware: %{}}} = group} = device, nil, now) do
    case Updates.update_status(device, group, now) do
      :up_to_date -> :up_to_date
      :updates_off -> :updates_off
      :deployment_group_inactive -> :group_paused
      :update_available -> {:waiting, group.current_release.firmware.version}
      :updates_blocked -> blocked_state(device, group.current_release.firmware.version)
      :unknown -> nil
    end
  end

  def update_state(%Device{update_mode: :off}, nil, _now), do: :updates_off
  def update_state(_device, nil, _now), do: nil

  # In the penalty box after failing to take the release, or held back
  # without a failure behind it (a device that asked to be rescheduled).
  defp blocked_state(%Device{consecutive_failed_updates: failures}, version) when failures > 0,
    do: {:failing, version, failures}

  defp blocked_state(device, _version), do: {:blocked, device.updates_blocked_until}

  defp inflight_version(%Device{inflight_update: %{firmware: %{version: version}}}), do: version
  defp inflight_version(_device), do: nil

  attr(:device, Device, required: true)
  attr(:progress, :map, default: nil, doc: "the update in progress the page is tracking, if any")

  @doc "The firmware a device runs, and where it stands on its updates."
  def firmware(assigns) do
    assigns = assign(assigns, :state, update_state(assigns.device, assigns.progress))

    ~H"""
    <div class="flex items-center gap-2 whitespace-nowrap">
      <span class={["font-mono text-ui/4", if(@device.firmware_metadata, do: "text-content-strong", else: "text-content-faint")]}>
        {if @device.firmware_metadata, do: @device.firmware_metadata.version, else: "Unknown"}
      </span>
      <.update_state state={@state} />
    </div>
    """
  end

  attr(:state, :any, required: true)

  defp update_state(%{state: nil} = assigns), do: ~H""

  defp update_state(%{state: :up_to_date} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 text-xs text-content-muted">
      <span class="lucide-check size-3 text-content-faint" aria-hidden="true"></span>Up to date
    </span>
    """
  end

  defp update_state(%{state: :updates_off} = assigns) do
    ~H"""
    <span class="text-xs text-content-faint">Updates off</span>
    """
  end

  defp update_state(%{state: :group_paused} = assigns) do
    ~H"""
    <span class="text-xs text-content-faint">Group paused</span>
    """
  end

  defp update_state(%{state: {:waiting, version}} = assigns) do
    assigns = assign(assigns, :version, version)

    ~H"""
    <span class="text-xs text-content-muted"><span class="font-mono">{@version}</span> waiting</span>
    """
  end

  defp update_state(%{state: {:blocked, until}} = assigns) do
    assigns = assign(assigns, :until, until)

    ~H"""
    <span class="inline-flex items-center gap-1 text-xs text-warning-content">
      <span class="lucide-clock size-3" aria-hidden="true"></span>Penalty box, {left(@until)} left
    </span>
    """
  end

  defp update_state(%{state: {:failing, version, failures}} = assigns) do
    assigns = assign(assigns, version: version, failures: failures)

    ~H"""
    <span class="inline-flex items-center gap-1 text-xs text-alert-content">
      <span class="lucide-x size-3" aria-hidden="true"></span>
      <span><span class="font-mono">{@version}</span> failed {if @failures == 1, do: "once", else: "#{@failures} times"}</span>
    </span>
    """
  end

  defp update_state(%{state: {:updating, progress, version}} = assigns) do
    assigns = assign(assigns, progress: %{stage: progress[:stage], percent: progress[:percent] || 0}, version: version)

    ~H"""
    <span class="inline-flex items-center gap-1.5 text-xs text-notice-content">
      <span :if={@version}>→ <span class="font-mono">{@version}</span></span>
      <span :if={@progress.percent > 0} class="flex h-1 w-12 rounded-full bg-line-subtle" aria-hidden="true">
        <span class="h-1 rounded-full bg-primary" style={"width: #{min(@progress.percent, 100)}%"}></span>
      </span>
      <span class="font-mono text-2xs/3.5 text-content-muted">
        {if @progress.percent > 0, do: "#{@progress.stage} #{@progress.percent}%", else: @progress.stage}
      </span>
    </span>
    """
  end

  # "Asleep, 9 minutes left" or "Overdue 25 minutes", counted from when the
  # device said it would be back.
  defp sleep_summary("overdue", %{expected_wake_at: %DateTime{} = at}),
    do: "Overdue #{Fleet.duration(max(DateTime.diff(DateTime.utc_now(), at), 0))}"

  defp sleep_summary("overdue", _connection), do: "Overdue"

  defp sleep_summary(_asleep, %{expected_wake_at: %DateTime{} = at}) do
    if DateTime.after?(at, DateTime.utc_now()), do: "Asleep, #{left(at)} left", else: "Asleep, due back now"
  end

  defp sleep_summary(_asleep, _connection), do: "Asleep"

  # "2 hours", or "a minute" for anything under one.
  defp left(until) do
    case DateTime.diff(until, DateTime.utc_now()) do
      seconds when seconds < 60 -> "a minute"
      seconds -> Fleet.duration(seconds)
    end
  end

  attr(:device, Device, required: true)

  attr(:status, :string,
    default: nil,
    doc:
      ~s("online", "offline", or "asleep" or "overdue" for a device that said it was going to sleep, as the page tracks it)
  )

  @doc """
  How long a device has been connected, or how long since it was last seen.
  A device not seen in #{@not_seen_days} days or more is in red, as is one
  whose last connection is older than any connection record
  (`Connections.last_seen_unrecorded?/2`).
  """
  def connection(%{status: "online"} = assigns) do
    ~H"""
    <span class="text-ui/4 text-content-body">{connected_for(@device.latest_connection) || "Online"}</span>
    """
  end

  def connection(%{status: status} = assigns) when status in ["asleep", "overdue"] do
    assigns = assign(assigns, :summary, sleep_summary(status, assigns.device.latest_connection))

    ~H"""
    <span
      class={["text-ui/4", if(@status == "overdue", do: "text-warning-content", else: "text-content-body")]}
      title={DeviceSleep.describe(@device.latest_connection)}
    >
      {@summary}
    </span>
    """
  end

  def connection(%{device: %Device{latest_connection: %{last_seen_at: %DateTime{} = seen}}} = assigns) do
    assigns = assign(assigns, :seconds, max(DateTime.diff(DateTime.utc_now(), seen), 0))

    ~H"""
    <span :if={@seconds >= not_seen_seconds()} class="text-ui/4 text-alert-content" title="Last seen">
      Not seen in {Fleet.duration(@seconds)}
    </span>
    <span :if={@seconds < not_seen_seconds()} class="text-ui/4 text-content-muted" title="Last seen">
      Offline {Fleet.duration(@seconds)}
    </span>
    """
  end

  def connection(assigns) do
    assigns =
      assign(assigns, :unrecorded?, Connections.last_seen_unrecorded?(assigns.device, assigns.device.latest_connection))

    ~H"""
    <span :if={@unrecorded?} class="text-ui/4 text-alert-content" title="Last connected before connection records were kept">
      Last seen unknown
    </span>
    <span :if={!@unrecorded?} class="text-ui/4 text-content-faint">Never connected</span>
    """
  end

  @doc ~s(How long a connection has been up, as "for 3 hours", or nil when it has no start.)
  @spec connected_for(map() | nil) :: String.t() | nil
  def connected_for(%{established_at: %DateTime{} = at}),
    do: "for #{Fleet.duration(max(DateTime.diff(DateTime.utc_now(), at), 0))}"

  def connected_for(_connection), do: nil

  defp not_seen_seconds(), do: DeviceFiltering.not_seen_seconds()

  attr(:pager, :map, required: true, doc: "with `current_page`, `total_pages`, `page_size` and `total_count`")
  attr(:page_sizes, :list, default: [25, 50, 100])
  attr(:id, :string, default: "device-pager")
  attr(:noun, :string, default: nil, doc: "what's counted, after the total: `58 unresolved`")

  @doc """
  The line under the list: which devices of how many it shows, then the page
  size and the page, between previous and next buttons. A phone shows which
  devices above the list instead.

  Sends `set-paginate-opts` with `page-size`, and `paginate` with `page`, as
  the shared pagers do.
  """
  def pager(assigns) do
    %{current_page: page, page_size: size, total_count: total, total_pages: pages} = assigns.pager

    assigns =
      assign(assigns,
        first: (page - 1) * size + 1,
        last: min(page * size, total),
        last_page: max(pages, 1)
      )

    ~H"""
    <div :if={@pager.total_count > 0} id={@id} class="flex items-center justify-between gap-4 pt-4 max-sm:justify-end">
      <p class="text-ui/4 text-content-muted max-sm:hidden">
        <span class="font-mono text-xs text-content-strong">{delimited(@first)}–{delimited(@last)}</span>
        of <span class="font-mono text-xs text-content-strong">{delimited(@pager.total_count)}</span>{if @noun, do: " #{@noun}"}
      </p>
      <div class="flex items-center gap-4">
        <form id={"#{@id}-size"} phx-change="set-paginate-opts" class="flex items-center gap-1.5">
          <label for={"#{@id}-size-select"} class="text-ui/4 text-content-muted">Per page</label>
          <div class="grid grid-cols-1">
            <select
              id={"#{@id}-size-select"}
              name="page-size"
              class="col-start-1 row-start-1 h-7 cursor-pointer appearance-none rounded border border-line-control bg-surface-raised bg-none py-0 pr-6 pl-2 font-mono text-xs text-content-strong focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
            >
              <option :for={size <- @page_sizes} value={size} selected={size == @pager.page_size}>{size}</option>
            </select>
            <span class="pointer-events-none col-start-1 row-start-1 mr-2 lucide-chevron-down size-3 self-center justify-self-end text-content-faint" aria-hidden="true"></span>
          </div>
        </form>
        <nav aria-label="Pages" class="flex h-7 items-center">
          <button
            type="button"
            aria-label="Previous page"
            disabled={@pager.current_page < 2}
            phx-click="paginate"
            phx-value-page={@pager.current_page - 1}
            class={[page_button_class(), "rounded-l"]}
          >
            <span class="lucide-chevron-left size-3.5" aria-hidden="true"></span>
          </button>
          <span class="flex h-7 items-center border-y border-line-default bg-surface-raised px-2.5 font-mono text-xs text-content-strong">
            {@pager.current_page} / {@last_page}
          </span>
          <button
            type="button"
            aria-label="Next page"
            disabled={@pager.current_page >= @last_page}
            phx-click="paginate"
            phx-value-page={@pager.current_page + 1}
            class={[page_button_class(), "rounded-r"]}
          >
            <span class="lucide-chevron-right size-3.5" aria-hidden="true"></span>
          </button>
        </nav>
      </div>
    </div>
    """
  end

  # Skeletons for the list's first load, drawn to the same widths and row
  # heights as what replaces them, so nothing moves when it arrives. A bar's
  # width varies down the rows, as real identifiers and versions would.
  @bar "animate-pulse rounded-full bg-base-800 motion-reduce:animate-none"
  @widths %{
    identifier: ~w(w-36 w-32 w-40 w-28 w-36 w-30),
    version: ~w(w-10 w-9 w-10 w-11),
    detail: ~w(w-20 w-14 w-24 w-16 w-0),
    group: ~w(w-24 w-20 w-28 w-14),
    connection: ~w(w-16 w-20 w-14),
    tags: ~w(w-12 w-10 w-14 w-0)
  }

  defp bar_width(kind, row), do: Enum.at(@widths[kind], rem(row, length(@widths[kind])))

  @headers %{
    health: {"Health", "w-28", nil},
    firmware: {"Firmware", "w-60", nil},
    platform: {"Platform", "w-20", nil},
    deployment_group: {"Deployment group", "w-40", nil},
    connected_info: {"Connection", "w-32", "connection_established_at"},
    tags: {"Tags", nil, "tags"}
  }

  attr(:columns, :list, required: true, doc: "the columns shown, in the table's order")
  attr(:rows, :integer, required: true)
  attr(:sort, :string, required: true)
  attr(:sort_direction, :string, required: true)

  @doc """
  The table while the list first loads: its real header, with the columns the
  user shows, over rows of placeholders. Below `sm`, cards like the list's.
  """
  def table_skeleton(assigns) do
    assigns = assign(assigns, headers: @headers, bar: @bar)

    ~H"""
    <div id="device-list-skeleton" aria-busy="true" aria-label="Loading devices">
      <div class="box-content flex h-8 items-center justify-between gap-3 pt-0.5 pb-2.5 sm:hidden" aria-hidden="true">
        <span class={["h-2 w-24", @bar]}></span>
        <span class="flex items-center gap-3">
          <span class={["h-2 w-20", @bar]}></span>
          <span class="h-8 w-15 rounded border border-line-default bg-surface-raised"></span>
        </span>
      </div>
      <%!-- Rows the heights of a card's: identifier and health, firmware,
            then group and connection. --%>
      <ul class="flex flex-col gap-2 sm:hidden" aria-hidden="true">
        <li :for={row <- 0..(@rows - 1)} class="flex flex-col gap-2 rounded-card border border-line-default bg-surface-raised p-3">
          <span class="flex h-4.5 items-center gap-2">
            <.status_dot class="mr-1.25 size-1.75 shrink-0 bg-status-offline" />
            <span class={["h-2.5", bar_width(:identifier, row), @bar]}></span>
            <span class={["ml-auto h-2 w-12", @bar]}></span>
          </span>
          <span class="flex h-4 items-center pl-5">
            <span class={["h-2", bar_width(:version, row), @bar]}></span>
          </span>
          <span class="flex h-6 items-center justify-between pl-5">
            <span class={["h-2", bar_width(:group, row), @bar]}></span>
            <span class={["h-2", bar_width(:connection, row), @bar]}></span>
          </span>
        </li>
      </ul>
      <div class="w-max min-w-full overflow-clip rounded-card border border-line-default bg-surface-raised max-sm:hidden">
        <table class="w-full text-left">
          <thead>
            <tr class="h-9 border-b border-line-default bg-surface [&>th]:pr-4 [&>th]:text-label [&>th]:text-content-faint [&>th]:uppercase">
              <th class="w-8 p-0">
                <span class="flex h-9 w-10 items-center pl-4" aria-hidden="true">
                  <span class="size-3.5 rounded-xs border border-line-control bg-surface-raised"></span>
                </span>
              </th>
              <th class="w-52">
                <Sorting.sort_icon text="Device" field="identifier" selected_field={@sort} selected_direction={@sort_direction} />
              </th>
              <th :for={column <- @columns} class={elem(@headers[column], 1)}>
                <% {label, _width, field} = @headers[column] %>
                <span :if={is_nil(field)}>{label}</span>
                <Sorting.sort_icon :if={field} text={label} field={field} selected_field={@sort} selected_direction={@sort_direction} />
              </th>
              <th class="w-16"><span class="sr-only">Peek</span></th>
            </tr>
          </thead>
          <tbody aria-hidden="true">
            <tr :for={row <- 0..(@rows - 1)} class="h-11 border-b border-line-subtle last:border-b-0 [&>td]:pr-4">
              <td class="p-0">
                <span class="flex h-11 w-10 items-center pl-4">
                  <span class="size-3.5 rounded-xs border border-line-control bg-surface-raised"></span>
                </span>
              </td>
              <td>
                <span class="flex items-center gap-2">
                  <.status_dot class="mr-1.25 size-1.75 bg-status-offline" />
                  <span class={["h-2.5", bar_width(:identifier, row), @bar]}></span>
                </span>
              </td>
              <td :for={column <- @columns}>
                <.skeleton_cell column={column} row={row} bar={@bar} />
              </td>
              <td></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr(:column, :atom, required: true)
  attr(:row, :integer, required: true)
  attr(:bar, :string, required: true)

  defp skeleton_cell(%{column: :health} = assigns) do
    ~H"""
    <span class={["block h-2 w-14", @bar]}></span>
    """
  end

  defp skeleton_cell(%{column: :firmware} = assigns) do
    ~H"""
    <span class="flex items-center gap-2">
      <span class={["h-2.5", bar_width(:version, @row), @bar]}></span>
      <span :if={bar_width(:detail, @row) != "w-0"} class={["h-2", bar_width(:detail, @row), @bar]}></span>
    </span>
    """
  end

  defp skeleton_cell(%{column: :platform} = assigns) do
    ~H"""
    <span class={["block h-2 w-10", @bar]}></span>
    """
  end

  defp skeleton_cell(%{column: :deployment_group} = assigns) do
    ~H"""
    <span class={["block h-2.5", bar_width(:group, @row), @bar]}></span>
    """
  end

  defp skeleton_cell(%{column: :connected_info} = assigns) do
    ~H"""
    <span class={["block h-2", bar_width(:connection, @row), @bar]}></span>
    """
  end

  defp skeleton_cell(%{column: :tags} = assigns) do
    ~H"""
    <span class="flex items-center gap-1">
      <span :if={bar_width(:tags, @row) != "w-0"} class={["h-5 rounded border border-line-default", bar_width(:tags, @row)]}></span>
    </span>
    """
  end

  attr(:rows, :integer, required: true)

  @doc "The Needs attention list while it first loads: rows of placeholders the height of its rows."
  def attention_skeleton(assigns) do
    assigns = assign(assigns, :bar, @bar)

    ~H"""
    <ul
      id="attention-list-skeleton"
      aria-busy="true"
      aria-label="Loading devices"
      class="overflow-clip rounded-card border border-line-default bg-surface-raised max-sm:flex max-sm:flex-col max-sm:gap-2 max-sm:overflow-visible max-sm:border-0 max-sm:bg-transparent"
    >
      <li
        :for={row <- 0..(@rows - 1)}
        aria-hidden="true"
        class="flex h-15 items-center gap-3 border-b border-line-subtle pr-5 pl-4 last:border-b-0 max-sm:h-auto max-sm:items-start max-sm:gap-2 max-sm:rounded-card max-sm:border max-sm:border-line-default max-sm:bg-surface-raised max-sm:p-3 max-sm:last:border-b"
      >
        <.status_dot class="mr-1.25 size-1.75 shrink-0 bg-status-offline max-sm:mt-1.75" />
        <span class="flex min-w-0 grow flex-col gap-2 max-sm:gap-2.5">
          <span class={["h-2.5", bar_width(:identifier, row), @bar]}></span>
          <span class={["h-2", Enum.at(~w(w-56 w-44 w-64 w-40), rem(row, 4)), @bar]}></span>
        </span>
      </li>
    </ul>
    """
  end

  @doc "The pager while the list first loads: its controls, without a range or a page yet."
  def pager_skeleton(assigns) do
    assigns = assign(assigns, :bar, @bar)

    ~H"""
    <div id="device-pager-skeleton" class="flex items-center justify-between gap-4 pt-4 max-sm:justify-end" aria-hidden="true">
      <span class={["h-2 w-28 max-sm:hidden", @bar]}></span>
      <div class="flex items-center gap-4">
        <span class="flex items-center gap-1.5">
          <span class="text-ui/4 text-content-muted">Per page</span>
          <span class="h-7 w-13 rounded border border-line-default bg-surface-raised"></span>
        </span>
        <span class="flex h-7 items-center">
          <span class="size-7 rounded-l border border-line-default bg-surface-raised"></span>
          <span class="flex h-7 w-14 items-center justify-center border-y border-line-default bg-surface-raised">
            <span class={["h-2 w-7", @bar]}></span>
          </span>
          <span class="size-7 rounded-r border border-line-default bg-surface-raised"></span>
        </span>
      </div>
    </div>
    """
  end

  defp page_button_class(),
    do:
      "flex size-7 shrink-0 items-center justify-center border bg-surface-raised enabled:cursor-pointer enabled:border-line-control enabled:text-content-body enabled:hover:bg-surface-muted enabled:hover:text-content-strong disabled:border-line-default disabled:text-content-faint"

  defp delimited(nil), do: "0"
  defp delimited(count), do: number_to_delimited(count, precision: 0)
end
