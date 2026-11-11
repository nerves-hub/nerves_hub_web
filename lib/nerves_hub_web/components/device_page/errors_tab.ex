defmodule NervesHubWeb.Components.DevicePage.ErrorsTab do
  @moduledoc """
  The errors one device has reported, grouped into issues.

  Rows are issues rather than occurrences: a device in a crash loop produces
  hundreds of the latter and one of the former, and the list that says "this
  device has three problems" is more use than the one that says "this device has
  four thousand errors".

  Expanding a row fetches that issue's most recent occurrence **on this device**
  — its stacktrace, its context, and what the device looked like at the time.
  The fleet-wide view of the same issue lives on the product's Errors page,
  which each row links to.

  ## Refreshing

  New occurrences arrive on the device's topic, but a row here is an aggregate,
  so there is nothing to insert — the list has to be recomputed. Recomputing it
  per occurrence would mean two queries per crash, which is the worst possible
  moment to be making them, so an arriving occurrence schedules a refresh
  instead and a crash loop collapses into one refresh every few seconds.
  """

  use NervesHubWeb, tab_component: :errors

  alias NervesHub.ErrorReports
  alias NervesHub.ErrorReports.ErrorReport
  alias NervesHub.Firmwares
  alias NervesHubWeb.Helpers.Timezone

  @refresh_delay to_timeout(second: 3)

  def tab_params(_params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> assign(:analytics_enabled, true)
      |> assign(:streaming_enabled, true)
      |> assign(:refresh_scheduled, false)
      |> assign(:expanded_fingerprint, nil)
      |> assign(:expanded_occurrence, nil)
      |> assign(:expanded_firmware_version, nil)
      |> fetch_error_groups()
      |> cont()
    else
      socket
      |> assign(:analytics_enabled, false)
      |> assign(:streaming_enabled, false)
      |> cont()
    end
  end

  # Only assigns this tab alone owns. `:analytics_enabled` and
  # `:streaming_enabled` are named the same way by other tabs, and `cleanup/0`
  # runs for every inactive tab in `@tab_components` order — so listing a shared
  # key here deletes it out from under whichever earlier tab is the active one.
  def cleanup() do
    [:refresh_scheduled, :expanded_fingerprint, :expanded_occurrence, :expanded_firmware_version, :error_groups]
  end

  # Also moves the count beside the tab's name, which the page reads once
  # when it mounts.
  defp fetch_error_groups(socket) do
    device = socket.assigns.device

    socket
    |> assign(:error_groups, ErrorReports.groups_for_device(device))
    |> assign(:error_issue_count, ErrorReports.issue_count_for_device(device))
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("toggle-error-streaming", _params, socket) do
    socket
    |> assign(:streaming_enabled, !socket.assigns.streaming_enabled)
    |> then(fn socket ->
      # Resuming refetches, so nothing that arrived while paused is missed.
      if socket.assigns.streaming_enabled, do: fetch_error_groups(socket), else: socket
    end)
    |> halt()
  end

  def hooked_event("toggle-error-details", %{"fingerprint" => fingerprint}, socket) do
    if socket.assigns.expanded_fingerprint == fingerprint do
      socket
      |> assign(:expanded_fingerprint, nil)
      |> assign(:expanded_occurrence, nil)
      |> assign(:expanded_firmware_version, nil)
      |> halt()
    else
      socket
      |> assign(:expanded_fingerprint, fingerprint)
      |> assign_expanded_occurrence()
      |> halt()
    end
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "error_reports:received"}, socket) do
    socket
    |> maybe_schedule_refresh()
    |> halt()
  end

  def hooked_info(:refresh_error_groups, socket) do
    socket
    |> assign(:refresh_scheduled, false)
    |> fetch_error_groups()
    |> refresh_expanded()
    |> halt()
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  defp maybe_schedule_refresh(%{assigns: %{streaming_enabled: false}} = socket), do: socket
  defp maybe_schedule_refresh(%{assigns: %{refresh_scheduled: true}} = socket), do: socket

  defp maybe_schedule_refresh(socket) do
    _ = Process.send_after(self(), :refresh_error_groups, @refresh_delay)

    assign(socket, :refresh_scheduled, true)
  end

  # An open row is showing an occurrence that may no longer be the newest.
  defp refresh_expanded(%{assigns: %{expanded_fingerprint: nil}} = socket), do: socket

  defp refresh_expanded(socket), do: assign_expanded_occurrence(socket)

  defp assign_expanded_occurrence(socket) do
    occurrence = latest_occurrence(socket, socket.assigns.expanded_fingerprint)

    socket
    |> assign(:expanded_occurrence, occurrence)
    |> assign(:expanded_firmware_version, firmware_version(socket.assigns.product, occurrence))
  end

  # The occurrence names the firmware by UUID; the version is what a reader
  # recognises. Firmware the product no longer has keeps just its UUID.
  defp firmware_version(product, %{firmware_uuid: uuid}) when uuid != "" do
    case Firmwares.get_firmware_by_product_and_uuid(product, uuid) do
      {:ok, firmware} -> firmware.version
      {:error, :not_found} -> nil
    end
  end

  defp firmware_version(_product, _occurrence), do: nil

  defp latest_occurrence(socket, fingerprint) do
    socket.assigns.error_groups
    |> Enum.find(&(&1.group.fingerprint == fingerprint))
    |> case do
      nil -> nil
      %{group: group} -> ErrorReports.latest_occurrence(group, device_id: socket.assigns.device.id)
    end
  end

  def render(%{analytics_enabled: false} = assigns) do
    ~H"""
    <.unavailable title="Analytics aren't enabled for your platform." detail="Check with your Ops team for more information." />
    """
  end

  def render(%{product: %{extensions: %{error_reports: false}}} = assigns) do
    ~H"""
    <.unavailable title="Error reports aren't enabled for this product." detail="Please check the product settings." />
    """
  end

  def render(%{device: %{extensions: %{error_reports: false}}} = assigns) do
    ~H"""
    <.unavailable title="Error reports aren't enabled for this device." detail="Please check the device settings." />
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="errors-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content w-full p-4 opacity-0 transition-all duration-500 sm:p-6 phx-click-loading:opacity-50"
    >
      <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <div class="flex min-h-12 shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-2 py-2 pr-3 pl-4">
          <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
            <h2 class="text-sm/4.5 font-semibold text-content-strong">Errors</h2>
            <span class="text-xs text-content-faint">Reported by this device in the last 30 days, grouped into issues</span>
          </div>
          <div class="flex items-center gap-2">
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
            <.button id="toggle-error-streaming" size="sm" phx-click="toggle-error-streaming" aria-pressed={to_string(!@streaming_enabled)}>
              <span class={[if(@streaming_enabled, do: "lucide-pause", else: "lucide-play"), "size-3.5 text-content-muted"]} aria-hidden="true"></span>
              {if @streaming_enabled, do: "Pause", else: "Resume"}
            </.button>
          </div>
        </div>

        <div :if={@error_groups == []} class="flex items-center justify-center border-t border-line-subtle p-14">
          <span class="text-ui text-content-faint">No errors have been reported.</span>
        </div>

        <div :if={@error_groups != []} class="overflow-x-auto px-4 pb-1">
          <table class="w-full min-w-2xl table-fixed text-left">
            <colgroup>
              <col class="w-34" />
              <col />
              <col class="w-31.5" />
              <col class="w-41.5" />
              <col class="w-4" />
            </colgroup>
            <thead class="border-t border-line-subtle">
              <tr class="text-label text-content-faint uppercase">
                <th class="h-8 pr-4 font-medium">Status</th>
                <th class="h-8 pr-4 font-medium">Error</th>
                <th class="h-8 pr-4 font-medium">On this device</th>
                <th class="h-8 pr-4 font-medium">Last seen</th>
                <th class="h-8"><span class="sr-only">Details</span></th>
              </tr>
            </thead>
            <%= for {entry, expanded?} <- Enum.map(@error_groups, &{&1, @expanded_fingerprint == &1.group.fingerprint}) do %>
              <%!-- The shadows carry an open issue's background out to the card's
                  edges, past the table's inset, as the rules stay inset. --%>
              <tbody class={[
                "border-t border-line-subtle",
                expanded? &&
                  "bg-surface-muted shadow-[-16px_0_var(--color-surface-muted),16px_0_var(--color-surface-muted)]"
              ]}>
                <tr
                  id={"error-group-#{entry.group.fingerprint}"}
                  phx-click="toggle-error-details"
                  phx-value-fingerprint={entry.group.fingerprint}
                  class={["h-15 cursor-pointer", !expanded? && "hover:bg-surface-muted"]}
                >
                  <td class="pr-4"><.status_badge status={entry.group.status} /></td>
                  <td class="py-2.5 pr-4">
                    <div class="truncate font-mono text-ui/4 text-content-strong" title={entry.group.reason}>{entry.group.reason}</div>
                    <div :if={entry.group.top_frame_module} class="truncate pt-0.75 font-mono text-xs text-content-faint">
                      {entry.group.top_frame_module}.{entry.group.top_frame_function}
                      <span :if={entry.group.top_frame_file}>{entry.group.top_frame_file}:{entry.group.top_frame_line}</span>
                    </div>
                  </td>
                  <td class="pr-4 text-ui font-medium text-content-strong">{entry.device_occurrence_count}</td>
                  <td class="pr-4 whitespace-nowrap">
                    <span class="text-ui font-medium text-content-strong">{day_label(entry.last_seen_at, @time_zone)}</span>
                    <.local_datetime
                      at={entry.last_seen_at}
                      time_zone={@time_zone}
                      format={:time_seconds}
                      zone_label={false}
                      class="ml-1.5 text-xs text-content-faint"
                    />
                  </td>
                  <td>
                    <%!-- A real button, not just the clickable row: a row with a
                          click handler is unreachable from the keyboard. --%>
                    <button
                      type="button"
                      phx-click="toggle-error-details"
                      phx-value-fingerprint={entry.group.fingerprint}
                      aria-expanded={to_string(expanded?)}
                      class="flex cursor-pointer text-content-faint hover:text-content-body aria-expanded:text-content-muted"
                    >
                      <span class={[if(expanded?, do: "lucide-chevron-down", else: "lucide-chevron-right"), "size-4"]} aria-hidden="true"></span>
                      <span class="sr-only">Details for {entry.group.reason}</span>
                    </button>
                  </td>
                </tr>
                <tr :if={expanded?}>
                  <td colspan="5" class="pt-1 pb-4.5 pl-34">
                    <.occurrence_details
                      occurrence={@expanded_occurrence}
                      firmware_version={@expanded_firmware_version}
                      group={entry.group}
                      org={@org}
                      product={@product}
                      time_zone={@time_zone}
                    />
                  </td>
                </tr>
              </tbody>
            <% end %>
          </table>
        </div>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:detail, :string, required: true)

  defp unavailable(assigns) do
    ~H"""
    <div class="w-full p-4 sm:p-6">
      <div class="flex flex-col items-center justify-center gap-1 rounded-card border border-line-default bg-surface-raised p-14 text-center shadow-card">
        <div class="text-ui font-medium text-content-strong">{@title}</div>
        <div class="text-xs text-content-faint">{@detail}</div>
      </div>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  defp status_badge(assigns) do
    ~H"""
    <span class={["inline-flex h-5 items-center gap-1.25 rounded px-1.75 text-xs font-medium whitespace-nowrap", status_class(@status)]}>
      <span class="size-1.5 rounded-full bg-current"></span>{@status |> Atom.to_string() |> String.capitalize()}
    </span>
    """
  end

  attr(:occurrence, :any, required: true)
  attr(:firmware_version, :string, default: nil)
  attr(:group, :any, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)
  attr(:time_zone, :string, required: true)

  defp occurrence_details(%{occurrence: nil} = assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <span class="text-xs text-content-muted">
        No stored occurrence — reports are kept for 30 days, and this issue's have aged out.
      </span>
      <.fleet_link group={@group} org={@org} product={@product} />
    </div>
    """
  end

  defp occurrence_details(assigns) do
    assigns = assign(assigns, :frames, ErrorReport.frames(assigns.occurrence))

    ~H"""
    <div class="flex flex-col gap-3.5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span class="text-xs font-medium text-content-muted">
          Latest occurrence on this device · {day_label(@occurrence.timestamp, @time_zone)}, <.local_datetime at={@occurrence.timestamp} time_zone={@time_zone} format={:time_seconds} zone_label={false} />
        </span>
        <.fleet_link group={@group} org={@org} product={@product} />
      </div>

      <div class="flex flex-wrap gap-x-5 gap-y-1.5 text-xs">
        <.fact label="kind" value={@occurrence.kind} />
        <.fact label="source" value={@occurrence.source} />
        <.fact :if={@occurrence.firmware_uuid != ""} label="firmware" value={firmware_label(@occurrence.firmware_uuid, @firmware_version)} />
        <%!-- Device vitals arrive as context, not as columns, so they render
              here alongside whatever else the application attached. --%>
        <.fact :for={{key, value} <- @occurrence.context} label={context_label(key)} value={context_value(key, value)} />
      </div>

      <div class="flex flex-col gap-0.5 overflow-x-auto rounded-card border border-line-subtle bg-surface-raised px-3.5 py-3 font-mono text-xs/4.5">
        <div class="max-h-40 overflow-y-auto whitespace-pre-wrap text-alert-content">{headline(@occurrence)}</div>
        <div :if={@frames != []} class="h-1.5 shrink-0"></div>
        <div :for={frame <- @frames} class="flex gap-4">
          <span class={["w-85 shrink-0", if(otp_frame?(frame), do: "text-content-muted", else: "text-content-strong")]}>
            {frame["module"]}.{frame["function"]}
          </span>
          <span :if={frame["file"]} class="text-content-faint">{frame["file"]}<span :if={frame["line"]}>:{frame["line"]}</span></span>
        </div>
      </div>

      <div :if={ErrorReport.truncated?(@occurrence)} class="text-xs text-content-faint">
        Truncated for storage — {format_bytes(@occurrence.payload_bytes)} were sent
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp fact(assigns) do
    ~H"""
    <span class="flex items-baseline gap-1.5">
      <span class="text-content-faint">{@label}</span>
      <span class="font-mono text-content-strong">{@value}</span>
    </span>
    """
  end

  attr(:group, :any, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)

  defp fleet_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/org/#{@org}/#{@product}/errors/#{@group.id}"}
      class="group flex items-center gap-1.5 text-xs font-medium text-content-body"
    >
      <span class="underline decoration-line-strong underline-offset-4 group-hover:decoration-content-muted">
        See this error across the fleet
      </span>
      <span class="lucide-arrow-right size-3 text-content-muted" aria-hidden="true"></span>
    </.link>
    """
  end

  # Erlang modules (`:gen_server`) are OTP's frames rather than the
  # application's, and stepping back from them points the eye at the code the
  # reader owns.
  defp otp_frame?(%{"module" => ":" <> _}), do: true
  defp otp_frame?(_frame), do: false

  # The message is the fuller account where the device sent one.
  defp headline(%{message: ""} = occurrence), do: occurrence.reason
  defp headline(occurrence), do: occurrence.message

  defp firmware_label(uuid, nil), do: String.slice(uuid, 0..7)
  defp firmware_label(uuid, version), do: "#{version} (#{String.slice(uuid, 0..7)})"

  # "Today" and "Yesterday" in the viewer's own zone, then the date.
  defp day_label(at, time_zone) do
    zone = Timezone.resolve(time_zone)
    date = at |> to_datetime() |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    today = DateTime.now!(zone) |> DateTime.to_date()

    case Date.diff(today, date) do
      0 -> "Today"
      1 -> "Yesterday"
      _ when date.year == today.year -> Calendar.strftime(date, "%b %-d")
      _ -> Calendar.strftime(date, "%b %-d, %Y")
    end
  end

  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_datetime(%DateTime{} = at), do: at

  # A handful of context keys have conventional names and units, and reading
  # "uptime_ms: 7200000" off a screen is work nobody should have to do. This is
  # the only place that knows about them: storage keeps context generic, so a
  # client with different vitals to report needs no change on this side.
  defp context_label("uptime_ms"), do: "uptime"
  defp context_label("free_memory_bytes"), do: "free memory"
  defp context_label("reboot_count"), do: "reboots"
  defp context_label(key), do: key

  defp context_value("uptime_ms", value), do: with_integer(value, &format_uptime/1)
  defp context_value("free_memory_bytes", value), do: with_integer(value, &format_bytes/1)
  defp context_value(_key, value), do: value

  # Context is a string map, and a device is free to put anything in it. A
  # value that is not the number the key implies is shown as it arrived rather
  # than formatted into a lie.
  defp with_integer(value, formatter) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> formatter.(parsed)
      _ -> value
    end
  end

  defp status_class(:unresolved), do: "bg-warning-soft text-warning-content"
  defp status_class(:resolved), do: "bg-success-soft text-success-content"
  defp status_class(:muted), do: "border border-line-default text-content-muted"

  defp format_uptime(milliseconds) do
    seconds = div(milliseconds, 1000)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      true -> "#{div(seconds, 86_400)}d"
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
end
