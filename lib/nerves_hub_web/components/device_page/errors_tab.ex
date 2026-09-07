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

  @refresh_delay to_timeout(second: 3)

  def tab_params(_params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> assign(:analytics_enabled, true)
      |> assign(:streaming_enabled, true)
      |> assign(:refresh_scheduled, false)
      |> assign(:expanded_fingerprint, nil)
      |> assign(:expanded_occurrence, nil)
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
    [:refresh_scheduled, :expanded_fingerprint, :expanded_occurrence, :error_groups]
  end

  defp fetch_error_groups(socket) do
    assign(socket, :error_groups, ErrorReports.groups_for_device(socket.assigns.device))
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
      |> halt()
    else
      socket
      |> assign(:expanded_fingerprint, fingerprint)
      |> assign(:expanded_occurrence, latest_occurrence(socket, fingerprint))
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

  defp refresh_expanded(socket) do
    fingerprint = socket.assigns.expanded_fingerprint

    assign(socket, :expanded_occurrence, latest_occurrence(socket, fingerprint))
  end

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
    <div class="size-full p-12">
      <div class="text-medium flex size-full flex-col items-center justify-center gap-6 p-6 font-mono">
        <div class="font-bold">Analytics aren't enabled for your platform.</div>
        <div>Check contact your Ops team for more information.</div>
      </div>
    </div>
    """
  end

  def render(%{product: %{extensions: %{error_reports: false}}} = assigns) do
    ~H"""
    <div class="size-full p-12">
      <div class="text-medium flex size-full flex-col items-center justify-center gap-6 p-6 font-mono">
        <div class="font-bold">Error reports aren't enabled for this product.</div>
        <div>Please check the product settings.</div>
      </div>
    </div>
    """
  end

  def render(%{device: %{extensions: %{error_reports: false}}} = assigns) do
    ~H"""
    <div class="size-full p-12">
      <div class="text-medium flex size-full flex-col items-center justify-center gap-6 p-6 font-mono">
        <div class="font-bold">Error reports aren't enabled for this device.</div>
        <div>Please check the device settings.</div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="errors-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="bg-base-950 phx-click-loading:opacity-50 tab-content size-full pb-10 opacity-0 transition-all duration-500"
    >
      <div class="border-base-700 flex h-11 flex-row items-center justify-between border-b px-12">
        <div>
          <span class="text-base-400 text-sm">Live updates :</span>
          <button
            id="toggle-error-streaming"
            type="button"
            phx-click="toggle-error-streaming"
            class={[
              "border-1.5 relative inline-flex h-3.5 w-6 shrink-0 cursor-pointer items-center rounded-full border-transparent transition-colors duration-200 ease-in-out focus:ring-0 focus:outline-none",
              (@streaming_enabled && "bg-success") || "bg-alert"
            ]}
            role="switch"
            aria-checked={to_string(@streaming_enabled)}
            aria-label="Toggle live updating of reported errors"
          >
            <span
              aria-hidden="true"
              class={[
                "pointer-events-none inline-block size-3",
                (@streaming_enabled && "translate-x-3") || "translate-x-0",
                "transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              ]}
            ></span>
          </button>
        </div>
        <span class="text-base-400 text-sm font-extralight">Errors reported in the last 30 days.</span>
      </div>

      <div :if={@error_groups == []} class="text-medium flex size-full items-center justify-center gap-6 p-6 font-mono">
        <div>No errors have been reported.</div>
      </div>

      <div :if={@error_groups != []} class="scrollable-inner size-full overflow-x-auto px-12 pt-6">
        <table class="w-full table-fixed font-mono text-sm">
          <colgroup>
            <col class="w-28" />
            <col />
            <col class="w-20" />
            <col class="w-52" />
            <col class="w-8" />
          </colgroup>
          <thead>
            <tr class="border-base-700 text-base-400 border-b text-left font-extralight">
              <th class="py-2 pr-6 font-normal">Status</th>
              <th class="py-2 pr-6 font-normal">Error</th>
              <th class="py-2 pr-6 font-normal">Count</th>
              <th class="py-2 pr-6 font-normal">Last seen (UTC)</th>
              <th class="py-2 font-normal"></th>
            </tr>
          </thead>
          <tbody>
            <%= for entry <- @error_groups do %>
              <tr
                id={"error-group-#{entry.group.fingerprint}"}
                phx-click="toggle-error-details"
                phx-value-fingerprint={entry.group.fingerprint}
                class="border-base-800 hover:bg-base-900 cursor-pointer border-b align-top"
              >
                <td class="py-2 pr-6">
                  <span class={["rounded px-1.5 py-0.5 text-xs", status_class(entry.group.status)]}>
                    {entry.group.status}
                  </span>
                </td>
                <td class="py-2 pr-6">
                  <div class="text-base-200 truncate" title={entry.group.reason}>{entry.group.reason}</div>
                  <div :if={entry.group.top_frame_module} class="text-base-500 truncate pt-0.5 text-xs">
                    {entry.group.top_frame_module}.{entry.group.top_frame_function}
                    <span :if={entry.group.top_frame_file}>({entry.group.top_frame_file}:{entry.group.top_frame_line})</span>
                  </div>
                </td>
                <td class="text-base-300 py-2 pr-6">{entry.device_occurrence_count}</td>
                <td class="text-base-300 py-2 pr-6 whitespace-nowrap">
                  {Calendar.strftime(entry.last_seen_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td class="py-2">
                  <%!-- A real button, not just the clickable row: a row with a
                        click handler is unreachable from the keyboard. --%>
                  <button
                    type="button"
                    phx-click="toggle-error-details"
                    phx-value-fingerprint={entry.group.fingerprint}
                    aria-expanded={to_string(@expanded_fingerprint == entry.group.fingerprint)}
                    aria-label={"Toggle details for #{entry.group.reason}"}
                    class="hover:text-base-300 text-base-500 cursor-pointer"
                  >
                    {(@expanded_fingerprint == entry.group.fingerprint && "−") || "+"}
                  </button>
                </td>
              </tr>
              <tr :if={@expanded_fingerprint == entry.group.fingerprint} class="border-base-800 border-b">
                <td colspan="5" class="px-2 py-4">
                  <.occurrence_details
                    occurrence={@expanded_occurrence}
                    group={entry.group}
                    org={@org}
                    product={@product}
                  />
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <div class="h-10"></div>
      </div>
    </div>
    """
  end

  attr(:occurrence, :any, required: true)
  attr(:group, :any, required: true)
  attr(:org, :any, required: true)
  attr(:product, :any, required: true)

  defp occurrence_details(%{occurrence: nil} = assigns) do
    ~H"""
    <div class="text-base-400 text-xs">
      No stored occurrence — reports are kept for 30 days, and this issue's have aged out.
    </div>
    """
  end

  defp occurrence_details(assigns) do
    assigns = assign(assigns, :frames, ErrorReport.frames(assigns.occurrence))

    ~H"""
    <div class="flex flex-col gap-3 text-xs">
      <div class="text-base-400 flex flex-row flex-wrap gap-x-6 gap-y-1">
        <span>kind: <span class="text-base-200">{@occurrence.kind}</span></span>
        <span>source: <span class="text-base-200">{@occurrence.source}</span></span>
        <span :if={@occurrence.firmware_uuid != ""}>
          firmware: <span class="text-base-200">{@occurrence.firmware_uuid}</span>
        </span>
        <%!-- Device vitals arrive as context, not as columns, so they render
              here alongside whatever else the application attached. --%>
        <span :for={{key, value} <- @occurrence.context}>
          {context_label(key)}: <span class="text-base-200">{context_value(key, value)}</span>
        </span>
      </div>

      <div :if={@occurrence.message != ""} class="text-base-300 max-h-40 overflow-y-auto whitespace-pre-wrap">
        {@occurrence.message}
      </div>

      <div :if={@frames != []} class="flex flex-col gap-0.5">
        <div :for={frame <- @frames} class="text-base-400">
          <span class="text-base-200">{frame["module"]}.{frame["function"]}</span>
          <span :if={frame["file"]}>&nbsp;({frame["file"]}<span :if={frame["line"]}>:{frame["line"]}</span>)</span>
        </div>
      </div>

      <div :if={ErrorReport.truncated?(@occurrence)} class="text-base-500">
        truncated for storage — {format_bytes(@occurrence.payload_bytes)} were sent
      </div>

      <div>
        <.link navigate={~p"/org/#{@org}/#{@product}/errors/#{@group.id}"} class="text-base-300 underline">
          See this error across the fleet
        </.link>
      </div>
    </div>
    """
  end

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

  defp status_class(:unresolved), do: "bg-base-800 text-orange-400"
  defp status_class(:resolved), do: "bg-base-800 text-success"
  defp status_class(:muted), do: "bg-base-800 text-base-400"

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
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
