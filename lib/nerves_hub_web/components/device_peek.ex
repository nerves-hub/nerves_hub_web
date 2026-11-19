defmodule NervesHubWeb.Components.DevicePeek do
  @moduledoc """
  The panel a row of the devices list opens (`NervesHubWeb.Live.Devices.Index`):
  enough about one device to decide whether to open it, without leaving the
  list.

  Its "why" section is about, in order of precedence: an update it keeps
  failing, a warning or unhealthy health report, how long since it was seen,
  or an update it is installing; a device with none of these has no such
  section. The list owns the device, its connection status and update progress; what
  the panel loads for itself (update attempts, recent activity, the latest
  metrics) arrives in `data`, and its sections show placeholders until then.
  """
  use NervesHubWeb, :component

  import NervesHubWeb.Helpers.Authorization, only: [authorized?: 2]

  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceFiltering
  alias NervesHubWeb.Components.DeviceList
  alias NervesHubWeb.Components.DevicePage.ActivityTab
  alias NervesHubWeb.Components.Fleet
  alias NervesHubWeb.Components.HealthStatus
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  # The metrics shown beside an unhealthy device's reasons, as
  # `{key, label, unit}`, in the order shown. Others stay on the Health tab.
  @metrics [
    {"mem_used_percent", "Memory", "%"},
    {"cpu_usage_percent", "CPU", "%"},
    {"cpu_temp", "Temperature", "°C"},
    {"load_1min", "Load", ""}
  ]

  @typedoc "What the \"why\" section is about, from `reason/3`."
  @type reason ::
          nil
          | {:failing, String.t(), pos_integer()}
          | {:health, map()}
          | {:not_seen, non_neg_integer() | nil}
          | {:updating, map(), String.t() | nil}

  @doc """
  What the panel's "why" section is about, if anything: an update the device
  keeps failing, a warning or unhealthy health report, not being seen for
  #{DeviceFiltering.not_seen_days()} days or more, or an update it is installing, in that order.
  How long it hasn't been seen is nil when its last connection is older than
  any connection record (`Connections.last_seen_unrecorded?/2`).
  """
  @spec reason(Device.t(), String.t() | nil, map() | nil) :: reason()
  def reason(device, status, progress) do
    case DeviceList.update_state(device, progress) do
      {:failing, version, failures} -> {:failing, version, failures}
      state -> health_reason(device, status, state)
    end
  end

  defp health_reason(%Device{latest_health: %{status: status} = health}, _status, _state)
       when status in [:warning, :unhealthy], do: {:health, health}

  defp health_reason(device, status, state) do
    not_seen = DeviceFiltering.not_seen_seconds()

    case {status, last_seen_seconds(device), state} do
      {"online", _seconds, {:updating, progress, version}} -> {:updating, progress, version}
      {"online", _seconds, _state} -> nil
      {_status, seconds, _state} when is_integer(seconds) and seconds >= not_seen -> {:not_seen, seconds}
      {_status, :unrecorded, _state} -> {:not_seen, nil}
      {_status, _seconds, {:updating, progress, version}} -> {:updating, progress, version}
      _ -> nil
    end
  end

  defp last_seen_seconds(%Device{latest_connection: %{last_seen_at: %DateTime{} = seen}}),
    do: max(DateTime.diff(DateTime.utc_now(), seen), 0)

  defp last_seen_seconds(%Device{latest_connection: connection} = device) do
    if Connections.last_seen_unrecorded?(device, connection), do: :unrecorded
  end

  attr(:device, Device, required: true)
  attr(:status, :string, default: nil, doc: ~s("online" or "offline", as the list tracks it))
  attr(:progress, :map, default: nil, doc: "the update in progress the list is tracking, if any")
  attr(:data, AsyncResult, required: true, doc: "`%{attempts:, attempt_count:, activity:, metrics:}`, loading at first")
  attr(:current_scope, :map, required: true)

  attr(:docked, :boolean,
    default: false,
    doc: "beside the list on a wide screen, which makes room for it, rather than over it"
  )

  @doc """
  The panel, fixed to the right of the page below the top bar. On a phone it
  is a sheet over the bottom of the list instead, with buttons for the
  previous and next device in place of the arrow keys.
  """
  def panel(assigns) do
    assigns =
      assigns
      |> assign(:reason, reason(assigns.device, assigns.status, assigns.progress))
      |> assign(:online?, assigns.status == "online")
      |> assign(:path, ~p"/org/#{assigns.current_scope.org}/#{assigns.current_scope.product}/devices/#{assigns.device}")

    ~H"""
    <div class="fixed inset-0 z-50 bg-backdrop sm:hidden" phx-click="close-peek" aria-hidden="true"></div>
    <aside
      id="device-peek"
      phx-hook="DevicePeek"
      data-device-id={@device.id}
      aria-labelledby="peek-title"
      class={[
        "fixed top-(--topbar-height) right-0 bottom-0 z-40 flex w-150 max-w-full flex-col border-l border-line-default bg-surface-raised shadow-[-12px_0_32px_-12px_rgb(0_0_0/0.18)]",
        "max-sm:top-auto max-sm:left-0 max-sm:z-50 max-sm:max-h-[88dvh] max-sm:w-full max-sm:rounded-t-xl max-sm:border-t max-sm:border-l-0 max-sm:shadow-[0_-12px_32px_rgb(0_0_0/0.18)]",
        @docked && "lg:shadow-none"
      ]}
    >
      <div class="mx-auto mt-2 h-1 w-9 shrink-0 rounded-full bg-line-strong sm:hidden" aria-hidden="true"></div>
      <div class="min-h-0 flex-1 overflow-y-auto pb-10 max-sm:pb-0">
        <header class="border-b border-line-default px-6 pt-5 pb-4.5 max-sm:px-4 max-sm:pt-3 max-sm:pb-3.5">
          <div class="flex items-center gap-3 max-sm:gap-2">
            <.status_dot class={["size-2 shrink-0", if(@online?, do: "bg-status-online", else: "bg-status-offline")]} />
            <h2 id="peek-title" class="min-w-0 truncate font-mono text-xl/6.5 font-medium text-content-strong max-sm:text-base/6">
              {@device.identifier}
            </h2>
            <.button type="link" size="sm" navigate={@path} data-peek-open class="ml-auto shrink-0 max-sm:hidden">
              Open device <span class="lucide-arrow-right size-3.5" aria-hidden="true"></span>
            </.button>
            <div class="ml-auto flex shrink-0 gap-1.5 sm:hidden">
              <.button type="button" square aria-label="Previous device" phx-click={JS.push("peek-move", value: %{by: -1})} class="max-sm:size-9">
                <span class="lucide-chevron-up size-4" aria-hidden="true"></span>
              </.button>
              <.button type="button" square aria-label="Next device" phx-click={JS.push("peek-move", value: %{by: 1})} class="max-sm:size-9">
                <span class="lucide-chevron-down size-4" aria-hidden="true"></span>
              </.button>
            </div>
            <.button type="button" size="sm" square aria-label="Close" title="Close" phx-click="close-peek" class="shrink-0 max-sm:size-9 max-sm:border-transparent">
              <span class="lucide-x size-3.5 max-sm:size-4" aria-hidden="true"></span>
            </.button>
          </div>
          <p class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 pl-5 text-ui/4 text-content-muted max-sm:mt-1.5 max-sm:pl-4">
            <span :if={@online?}><span class="font-medium text-success-content">Online</span> {DeviceList.connected_for(@device.latest_connection)}</span>
            <span :if={!@online?} class="font-medium text-content-body">Offline</span>
            <.dot_separator :if={@device.firmware_metadata} />
            <span :if={@device.firmware_metadata} class="font-mono text-xs">{@device.firmware_metadata.platform}</span>
            <.dot_separator :if={@device.deployment_group} />
            <span :if={@device.deployment_group}>{@device.deployment_group.name}</span>
            <.dot_separator :if={@device.firmware_metadata} />
            <span :if={@device.firmware_metadata} class="font-mono text-xs">{@device.firmware_metadata.version}</span>
          </p>
        </header>

        <.why reason={@reason} device={@device} data={@data} />

        <div class="flex flex-wrap items-center gap-2 border-b border-line-default px-6 py-4">
          <.button :if={@online? && authorized?(:"device:console", @current_scope)} type="link" size="sm" navigate={"#{@path}/console"}>
            <span class="lucide-terminal size-3.5" aria-hidden="true"></span> Console
          </.button>
          <.button :if={match?({:failing, _, _}, @reason)} type="link" size="sm" navigate={"#{@path}/firmware_history"}>
            <span class="lucide-list-restart size-3.5" aria-hidden="true"></span> Update attempts
          </.button>
          <.button :if={match?({:health, _}, @reason)} type="link" size="sm" navigate={"#{@path}/health"}>
            <span class="lucide-heart-pulse size-3.5" aria-hidden="true"></span> Health history
          </.button>
          <.button
            :if={authorized?(:"device:reboot", @current_scope)}
            type="button"
            size="sm"
            phx-click="peek-reboot"
            data-confirm={"Reboot #{@device.identifier}?"}
            disabled={!@online?}
            title={if !@online?, do: "The device is offline"}
          >
            <span class="lucide-rotate-ccw size-3.5" aria-hidden="true"></span> Reboot…
          </.button>
        </div>

        <section aria-labelledby="peek-activity" class="border-b border-line-default px-6 py-5">
          <h3 id="peek-activity" class="text-label font-medium tracking-[0.06em] text-content-faint uppercase">Recent activity</h3>
          <ul :if={!@data.ok?} class="mt-3 flex flex-col gap-3" aria-hidden="true">
            <li :for={_ <- 1..3} class="h-4 w-2/3 animate-pulse rounded bg-surface-muted"></li>
          </ul>
          <p :if={@data.ok? && @data.result.activity == []} class="mt-3 text-ui/4 text-content-faint">Nothing yet.</p>
          <ul :if={@data.ok? && @data.result.activity != []} id="peek-activity-entries" class="mt-2 flex flex-col">
            <li :for={entry <- @data.result.activity} class="flex min-h-8 items-center gap-2.5">
              <span class={[ActivityTab.kind_icon(entry.kind), "size-3.5 shrink-0 text-content-muted"]} aria-hidden="true"></span>
              <span class="min-w-0 grow truncate text-ui/4 text-content-body" title={entry.description}>{entry.description}</span>
              <span class="shrink-0 text-xs whitespace-nowrap text-content-faint">{ago(entry.inserted_at)}</span>
            </li>
          </ul>
          <.link navigate={"#{@path}/activity"} class="mt-2 inline-flex items-center gap-1 text-ui/4 text-content-muted hover:text-content-strong">
            All activity <span class="lucide-arrow-right size-3" aria-hidden="true"></span>
          </.link>
        </section>

        <dl class="px-6 [&>div]:flex [&>div]:min-h-9 [&>div]:items-center [&>div]:border-b [&>div]:border-line-subtle [&>div]:text-ui/4">
          <div>
            <dt class="w-33 shrink-0 text-content-muted">Deployment group</dt>
            <dd :if={@device.deployment_group} class="flex min-w-0 items-center gap-1.5 text-content-body">
              <.link
                navigate={~p"/org/#{@current_scope.org}/#{@current_scope.product}/deployment_groups/#{@device.deployment_group}"}
                class="truncate text-content-strong hover:underline hover:decoration-line-strong"
              >
                {@device.deployment_group.name}
              </.link>
              <.group_release device={@device} />
            </dd>
            <dd :if={!@device.deployment_group} class="text-content-faint">None</dd>
          </div>
          <div>
            <dt class="w-33 shrink-0 text-content-muted">{connection_label(@device, @online?)}</dt>
            <dd class="flex min-w-0 items-center gap-2 text-content-body">
              <span>{connection_time(@device, @online?)}</span>
              <span :if={@device.latest_connection && @device.latest_connection.ip_address} class="font-mono text-xs text-content-muted">
                {@device.latest_connection.ip_address}
              </span>
            </dd>
          </div>
          <div class="py-1.5">
            <dt class="w-33 shrink-0 text-content-muted">Tags</dt>
            <dd :if={@device.tags not in [nil, []]} class="flex flex-wrap gap-1">
              <.tag :for={tag <- @device.tags}>{tag}</.tag>
            </dd>
            <dd :if={@device.tags in [nil, []]} class="text-content-faint">None</dd>
          </div>
        </dl>
      </div>

      <div class="shrink-0 border-t border-line-default px-4 pt-3 pb-[max(--spacing(3),env(safe-area-inset-bottom))] sm:hidden">
        <.button type="link" style="primary" navigate={@path} class="h-11 w-full justify-center text-sm">
          Open device <span class="lucide-arrow-right size-3.5" aria-hidden="true"></span>
        </.button>
      </div>

      <footer class="absolute inset-x-0 bottom-0 flex h-10 items-center gap-5 border-t border-line-default bg-surface-raised px-6 text-xs text-content-muted max-sm:hidden">
        <span class="flex items-center gap-1.5"><.kbd>↑</.kbd><.kbd>↓</.kbd>
        Next device</span>
        <span class="flex items-center gap-1.5"><.kbd>↵</.kbd>
        Open device</span>
        <span class="flex items-center gap-1.5"><.kbd>esc</.kbd>
        Close</span>
      </footer>
    </aside>
    """
  end

  attr(:reason, :any, required: true)
  attr(:device, Device, required: true)
  attr(:data, AsyncResult, required: true)

  defp why(%{reason: nil} = assigns), do: ~H""

  defp why(%{reason: {:failing, version, failures}} = assigns) do
    assigns = assign(assigns, version: version, failures: failures)

    ~H"""
    <section id="peek-why" class="border-b border-line-default px-6 py-5">
      <p class="text-label font-medium tracking-[0.06em] text-alert-content uppercase">Update failing</p>
      <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">
        <span class="font-mono">{@version}</span> has failed {times(@failures)}{latest_reason(@data)}
      </p>
      <div :if={!@data.ok?} class="mt-4 h-24 animate-pulse rounded-card bg-surface-muted" aria-hidden="true"></div>
      <div :if={@data.ok? && @data.result.attempts != []} class="mt-4 overflow-hidden rounded-card border border-line-default">
        <table class="w-full text-left text-ui/4">
          <thead>
            <tr class="h-8 bg-surface-muted [&>th]:px-3 [&>th]:text-label [&>th]:font-medium [&>th]:text-content-faint [&>th]:uppercase">
              <th class="w-14">Try</th>
              <th class="w-28">When</th>
              <th class="w-24">Outcome</th>
              <th>Error</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{attempt, try} <- numbered(@data.result)} class="h-9 border-t border-line-subtle [&>td]:px-3">
              <td class="font-mono text-xs text-content-muted">#{try}</td>
              <td class="whitespace-nowrap text-content-body">{ago(attempt.timestamp)}</td>
              <td class={["whitespace-nowrap", outcome_colour(attempt.status)]}>{outcome(attempt.status)}</td>
              <td class="max-w-0 truncate text-content-body" title={attempt.reason}>{attempt.reason || "—"}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp why(%{reason: {:health, health}} = assigns) do
    assigns =
      assign(assigns,
        health: health,
        summary: upcase_first(DeviceList.health_summary(health)),
        lines: HealthStatus.reason_lines(health)
      )

    ~H"""
    <section id="peek-why" class="border-b border-line-default px-6 py-5">
      <p class={[
        "text-label font-medium tracking-[0.06em] uppercase",
        if(@health.status == :unhealthy, do: "text-alert-content", else: "text-warning-content")
      ]}>
        {if @health.status == :unhealthy, do: "Unhealthy", else: "Warning"}
      </p>
      <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">{@summary}</p>
      <p :for={line <- @lines} class="mt-1 text-ui/5 text-content-muted">{line}</p>
      <div :if={!@data.ok?} class="mt-4 h-15 animate-pulse rounded-card bg-surface-muted" aria-hidden="true"></div>
      <dl :if={@data.ok? && metrics(@data.result.metrics) != []} class="mt-4 grid grid-cols-4 overflow-hidden rounded-card border border-line-default">
        <div :for={{label, value} <- metrics(@data.result.metrics)} class="border-l border-line-subtle px-3 py-2.5 first:border-l-0">
          <dt class="text-label font-medium text-content-faint uppercase">{label}</dt>
          <dd class="mt-0.5 font-mono text-figure-sm text-content-strong">{value}</dd>
        </div>
      </dl>
    </section>
    """
  end

  defp why(%{reason: {:not_seen, nil}} = assigns) do
    ~H"""
    <section id="peek-why" class="border-b border-line-default px-6 py-5">
      <p class="text-label font-medium tracking-[0.06em] text-alert-content uppercase">Last seen unknown</p>
      <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">Last connected before connection records were kept</p>
      <p :if={@device.first_seen_at} class="mt-1 text-ui/5 text-content-muted">First seen {Calendar.strftime(@device.first_seen_at, "%-d %b %Y")}</p>
    </section>
    """
  end

  defp why(%{reason: {:not_seen, seconds}} = assigns) do
    assigns = assign(assigns, :seconds, seconds)

    ~H"""
    <section id="peek-why" class="border-b border-line-default px-6 py-5">
      <p class="text-label font-medium tracking-[0.06em] text-alert-content uppercase">Not seen in {Fleet.duration(@seconds)}</p>
      <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">
        Last seen {Calendar.strftime(@device.latest_connection.last_seen_at, "%-d %b %Y")}{last_ip(@device)}
      </p>
    </section>
    """
  end

  defp why(%{reason: {:updating, progress, version}} = assigns) do
    assigns = assign(assigns, stage: progress[:stage], percent: progress[:percent] || 0, version: version)

    ~H"""
    <section id="peek-why" class="border-b border-line-default px-6 py-5">
      <p class="text-label font-medium tracking-[0.06em] text-notice-content uppercase">Updating</p>
      <p class="mt-1.5 text-base/5.5 font-semibold text-content-strong">
        {if @version, do: "Installing ", else: "Installing an update"}<span :if={@version} class="font-mono">{@version}</span>
      </p>
      <div class="mt-3 flex items-center gap-3">
        <span class="flex h-1.5 flex-1 rounded-full bg-line-subtle" aria-hidden="true">
          <span class="h-1.5 rounded-full bg-primary" style={"width: #{min(@percent, 100)}%"}></span>
        </span>
        <span class="font-mono text-xs text-content-muted">{@stage} {@percent}%</span>
      </div>
    </section>
    """
  end

  attr(:device, Device, required: true)

  # Where the device stands against its group's release, beside the group's name.
  defp group_release(assigns) do
    assigns = assign(assigns, :state, DeviceList.update_state(assigns.device, nil))

    ~H"""
    <span :if={@state == :up_to_date} class="shrink-0 text-content-muted">up to date</span>
    <span :if={release_version(@state)} class="shrink-0 text-content-muted">
      wants <span class="font-mono text-xs">{release_version(@state)}</span>
    </span>
    <span :if={@state == :group_paused} class="shrink-0 text-content-faint">paused</span>
    """
  end

  defp release_version({:waiting, version}), do: version
  defp release_version({:failing, version, _failures}), do: version
  defp release_version(_state), do: nil

  slot(:inner_block, required: true)

  defp kbd(assigns) do
    ~H"""
    <kbd class="inline-flex h-4.5 min-w-4.5 items-center justify-center rounded-[3px] border border-line-default px-1 font-sans text-[11px]/3.5 text-content-muted">
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  defp dot_separator(assigns) do
    ~H"""
    <span class="text-content-faint" aria-hidden="true">·</span>
    """
  end

  defp connection_label(_device, true), do: "Connected"
  defp connection_label(%Device{latest_connection: %{last_seen_at: %DateTime{}}}, false), do: "Last seen"
  defp connection_label(device, false), do: if(unrecorded?(device), do: "Last seen", else: "Connection")

  defp connection_time(%Device{latest_connection: %{established_at: %DateTime{} = at}}, true), do: ago(at)
  defp connection_time(%Device{latest_connection: %{last_seen_at: %DateTime{} = at}}, false), do: ago(at)
  defp connection_time(device, _online?), do: if(unrecorded?(device), do: "Unknown", else: "Never connected")

  defp unrecorded?(%Device{latest_connection: connection} = device),
    do: Connections.last_seen_unrecorded?(device, connection)

  # "12 minutes ago", or "just now" under a minute.
  defp ago(%DateTime{} = at) do
    case DateTime.diff(DateTime.utc_now(), at) do
      seconds when seconds < 60 -> "just now"
      seconds -> "#{Fleet.duration(seconds)} ago"
    end
  end

  defp ago(%NaiveDateTime{} = at), do: ago(DateTime.from_naive!(at, "Etc/UTC"))

  defp times(1), do: "once"
  defp times(n), do: "#{n} times"

  # ": <the latest attempt's error>", once the attempts have loaded.
  defp latest_reason(%AsyncResult{ok?: true, result: %{attempts: [%{reason: reason} | _]}})
       when is_binary(reason) and reason != "", do: ": #{reason}"

  defp latest_reason(_data), do: ""

  # Attempts come newest first, so the newest is numbered the attempt count.
  defp numbered(%{attempts: attempts, attempt_count: count}) do
    Enum.with_index(attempts, fn attempt, index -> {attempt, count - index} end)
  end

  defp outcome(:succeeded), do: "Succeeded"
  defp outcome(:rescheduled), do: "Rescheduled"
  defp outcome(:failed), do: "Failed"
  defp outcome(:ignored), do: "Ignored"
  defp outcome(:expired), do: "Expired"
  defp outcome(:abandoned), do: "Abandoned"

  defp outcome_colour(:succeeded), do: "text-success-content"
  defp outcome_colour(:rescheduled), do: "text-content-muted"
  defp outcome_colour(_status), do: "text-alert-content"

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(text), do: text

  defp last_ip(%Device{latest_connection: %{ip_address: ip}}) when is_binary(ip), do: ", from #{ip}"
  defp last_ip(_device), do: ""

  # The latest values of the metrics the panel shows, as `{label, value}`.
  defp metrics(latest) do
    Enum.flat_map(@metrics, fn {key, label, unit} ->
      case latest[key] do
        value when is_number(value) -> [{label, "#{DeviceList.format_number(value)}#{unit}"}]
        _ -> []
      end
    end)
  end
end
