defmodule NervesHubWeb.Components.DevicePage.DataHistoryTab do
  @moduledoc """
  Shows what a device has sent and been sent, newest first.

  Reads `NervesHub.Devices.DeviceMessages` for the history and follows the
  device's internal topic for anything recorded while the tab is open, so a
  device being worked on can be watched rather than refreshed.

  Streaming can be paused. That is not a convenience — a device mid-update or
  with a console attached produces messages faster than anyone can read them,
  and the moment you want to look at one closely is the moment it scrolls away.
  Pausing freezes what is on screen; resuming refetches, so nothing that arrived
  while paused is missed.

  Filters live in the URL so a particular view of a device's traffic can be
  linked to, which is most of the point when someone is being asked to look at it.

  The first page is the newest messages, and "Show older messages" (or
  scrolling to it) adds the next page from the oldest one on screen, up to the
  most the tab will hold. Past that, as on the Logs tab, each new message pushes
  the oldest out, and paging is already off by then.

  A row opens in the browser alone, with no round trip, to show its payload
  laid out: a stream's rows are not kept on the server, so there is nothing
  there to mark as open.
  """

  use NervesHubWeb, tab_component: :data_history

  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Devices.DeviceMessages.Payload
  alias NervesHubWeb.Components.DateTimes
  alias NervesHubWeb.Components.DevicePage.TabNotice

  @page_size 100
  @max_messages 1_000

  def tab_params(params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> assign(:analytics_enabled, true)
      |> assign(:streaming_enabled, true)
      |> assign_filters(params)
      |> configure_stream()
      |> fetch_messages()
      |> cont()
    else
      socket
      |> assign(:analytics_enabled, false)
      |> assign(:streaming_enabled, false)
      |> cont()
    end
  end

  # `:analytics_enabled` and `:streaming_enabled` are deliberately absent: the
  # Logs and Errors tabs set them too, and an inactive tab that cleans a key
  # another tab sets deletes it out from under whichever of them is active. See
  # `NervesHubWeb.Components.DevicePage.TabCleanupTest`.
  def cleanup() do
    [:has_messages, :direction_filter, :topic_filter, :message_count, :message_cursor, :more_messages]
  end

  defp configure_stream(%{assigns: %{streams: %{messages: _}}} = socket), do: socket

  defp configure_stream(socket) do
    # Messages are append-only and never updated, and two can share a timestamp
    # to the microsecond, so identity comes from the insert rather than the row.
    stream_configure(socket, :messages,
      dom_id: fn _message -> "device-message-#{System.unique_integer([:positive, :monotonic])}" end
    )
  end

  defp assign_filters(socket, params) do
    socket
    |> assign(:direction_filter, filter_value(params, "direction", DeviceMessage.directions()))
    |> assign(:topic_filter, filter_value(params, "topic", DeviceMessage.topics()))
  end

  # An unrecognised filter shows everything rather than nothing. A hand-edited
  # or stale URL should not look like a device with no traffic.
  defp filter_value(params, key, allowed) do
    case Map.get(params, key) do
      value when value in [nil, "", "all"] -> "all"
      value -> if value in allowed, do: value, else: "all"
    end
  end

  # Asks for one more message than a page holds. If it comes back there is
  # something older to show, so the tab never offers a "Show older messages"
  # with nothing behind it.
  defp read_page(socket, size, extra_opts) do
    opts =
      [
        limit: size + 1,
        direction: query_filter(socket.assigns.direction_filter),
        topic: query_filter(socket.assigns.topic_filter)
      ] ++ extra_opts

    {page, older} = socket.assigns.device |> DeviceMessages.recent(opts) |> Enum.split(size)

    {page, older != []}
  end

  defp fetch_messages(socket) do
    {page, more?} = read_page(socket, @page_size, [])

    socket
    |> stream(:messages, page, reset: true)
    |> assign(:has_messages, page != [])
    |> assign(:message_count, length(page))
    |> assign(:message_cursor, oldest_timestamp(page, nil))
    |> assign(:more_messages, more?)
  end

  # Messages older than the oldest on screen. The cursor is exclusive, so two
  # messages in the same microsecond that straddle a page boundary lose the
  # second, as on the Logs tab.
  defp load_older(
         %{assigns: %{more_messages: true, message_cursor: %DateTime{} = cursor, message_count: count}} = socket
       )
       when count < @max_messages do
    {page, more?} = read_page(socket, min(@page_size, @max_messages - count), before: cursor)

    socket
    |> stream(:messages, page, at: -1)
    |> assign(:message_count, count + length(page))
    |> assign(:message_cursor, oldest_timestamp(page, cursor))
    |> assign(:more_messages, more?)
  end

  defp load_older(socket), do: socket

  defp oldest_timestamp([], fallback), do: fallback
  defp oldest_timestamp(page, _fallback), do: page |> List.last() |> Map.fetch!(:timestamp)

  defp query_filter("all"), do: nil
  defp query_filter(value), do: value

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("filter-messages", params, socket) do
    %{org: org, product: product, device: device} = socket.assigns

    socket = assign_filters(socket, params)

    query = %{
      "direction" => socket.assigns.direction_filter,
      "topic" => socket.assigns.topic_filter
    }

    socket
    |> fetch_messages()
    |> push_patch(to: ~p"/org/#{org}/#{product}/devices/#{device}/data_history?#{query}")
    |> halt()
  end

  def hooked_event("load-more-messages", _params, socket) do
    socket
    |> load_older()
    |> halt()
  end

  # Resuming refetches rather than picking up from the next broadcast, so the
  # gap that opened while paused is closed instead of being left as a silent
  # hole in the middle of the list.
  def hooked_event("toggle-streaming", _params, %{assigns: %{streaming_enabled: false}} = socket) do
    socket
    |> assign(:streaming_enabled, true)
    |> fetch_messages()
    |> halt()
  end

  def hooked_event("toggle-streaming", _params, socket) do
    socket
    |> assign(:streaming_enabled, false)
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: event, payload: message}, socket) do
    if event == DeviceMessages.broadcast_event() do
      halt(maybe_stream(socket, message))
    else
      {:cont, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  defp maybe_stream(%{assigns: %{streaming_enabled: false}} = socket, _message), do: socket

  defp maybe_stream(socket, message) do
    if matches_filters?(socket, message) do
      %{message_count: count, more_messages: more?} = socket.assigns

      # Once the list is full the oldest is pushed out, so there is history
      # behind what is on screen whether or not there was before.
      socket
      |> stream_insert(:messages, message, at: 0, limit: @max_messages)
      |> assign(:message_count, min(count + 1, @max_messages))
      |> assign(:more_messages, more? or count >= @max_messages)
      |> assign(:has_messages, true)
    else
      socket
    end
  end

  defp matches_filters?(socket, message) do
    matches?(socket.assigns.direction_filter, message.direction) and
      matches?(socket.assigns.topic_filter, message.topic)
  end

  defp matches?("all", _value), do: true
  defp matches?(filter, value), do: filter == value

  def render(%{analytics_enabled: false} = assigns) do
    ~H"""
    <TabNotice.render title="Analytics aren't enabled for your platform." detail="Check with your Ops team for more information." />
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="data-history-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content w-full p-4 opacity-0 transition-all duration-500 sm:p-6 phx-click-loading:opacity-50"
    >
      <div class="flex w-full flex-col overflow-clip rounded-card border border-line-default bg-surface-raised shadow-card">
        <div class="flex min-h-14 shrink-0 flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-line-subtle px-4 py-2.5">
          <div class="flex flex-wrap items-center gap-2">
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
            <.button id="toggle-message-streaming" size="sm" phx-click="toggle-streaming" aria-pressed={to_string(!@streaming_enabled)}>
              <span class={[if(@streaming_enabled, do: "lucide-pause", else: "lucide-play"), "size-3.5 text-content-muted"]} aria-hidden="true"></span>
              {if @streaming_enabled, do: "Pause", else: "Resume"}
            </.button>

            <span class="mx-0.5 hidden h-5 w-px bg-line-default sm:block" aria-hidden="true"></span>

            <div role="group" aria-label="Direction" class="flex h-7.5 overflow-clip rounded border border-line-control">
              <button
                :for={{label, value} <- direction_options()}
                type="button"
                phx-click="filter-messages"
                phx-value-direction={value}
                phx-value-topic={@topic_filter}
                aria-pressed={to_string(value == @direction_filter)}
                class="flex cursor-pointer items-center border-l border-line-control px-3 text-ui text-content-body first:border-l-0 hover:bg-surface-muted aria-pressed:bg-surface-muted aria-pressed:font-medium aria-pressed:text-content-strong"
              >
                {label}
              </button>
            </div>

            <form id="data-history-filters" phx-change="filter-messages" class="grid grid-cols-1">
              <input type="hidden" name="direction" value={@direction_filter} />
              <select
                name="topic"
                aria-label="Channel"
                class="col-start-1 row-start-1 h-7.5 cursor-pointer appearance-none rounded border border-line-control border-b-line-strong bg-surface-raised bg-none py-0 pr-7 pl-2.5 text-ui text-content-body focus:outline focus:-outline-offset-1 focus:outline-focus-ring"
              >
                <option :for={{label, value} <- topic_options()} value={value} selected={value == @topic_filter}>{label}</option>
              </select>
              <span class="pointer-events-none col-start-1 row-start-1 mr-2 lucide-chevron-down size-3.5 self-center justify-self-end text-content-muted" aria-hidden="true"></span>
            </form>
          </div>
          <span class="text-xs text-content-faint">
            Newest first · last {@message_count} messages · times in {zone_abbr(@time_zone)}
          </span>
        </div>

        <div :if={!@has_messages} class="flex items-center justify-center p-14">
          <span class="text-ui text-content-faint">No messages have been recorded yet.</span>
        </div>

        <div :if={@has_messages} class="overflow-x-auto">
          <div class="min-w-4xl">
            <div class="flex h-10 items-center gap-4 border-b border-line-subtle px-4 text-label font-medium text-content-faint uppercase">
              <span class="w-28 shrink-0">Time</span>
              <span class="w-28 shrink-0">Direction</span>
              <span class="w-24 shrink-0">Channel</span>
              <span class="w-44 shrink-0">Event</span>
              <span class="grow">Data</span>
              <span class="w-4 shrink-0"></span>
            </div>

            <div id="device-messages" phx-update="stream" phx-hook="LogDayStarts">
              <div
                :for={{dom_id, message} <- @streams.messages}
                id={dom_id}
                data-day={DateTimes.day_key(message.timestamp, @time_zone)}
                class="group/line"
              >
                <%!-- Shown above the first message of each day; see the
                      LogDayStarts hook. --%>
                <div class="hidden h-8 items-center gap-2.5 border-b border-line-subtle px-4 group-data-day-start/line:flex">
                  <span class="text-label font-medium whitespace-nowrap text-content-faint uppercase">
                    {DateTimes.day_heading(message.timestamp, @time_zone)}
                  </span>
                  <span class="h-px grow bg-line-subtle"></span>
                </div>
                <div id={"#{dom_id}-row"} data-device-message aria-expanded="false" class="group/message border-b border-line-subtle aria-expanded:bg-surface-muted">
                  <button
                    type="button"
                    phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{dom_id}-row")}
                    class="flex h-10 w-full cursor-pointer items-center gap-4 px-4 text-left hover:bg-surface-muted"
                  >
                    <.local_datetime at={message.timestamp} time_zone={@time_zone} format={:log_time} zone_label={false} class="w-28 shrink-0 font-mono text-xs text-content-muted" />
                    <span class="flex w-28 shrink-0 items-center gap-1.5 text-ui text-content-body">
                      <span
                        class={[
                          if(message.direction == "sent", do: "lucide-arrow-up-right", else: "lucide-arrow-down-left"),
                          "size-3.5 text-content-muted"
                        ]}
                        aria-hidden="true"
                      ></span>
                      {direction_label(message.direction)}
                    </span>
                    <span class="w-24 shrink-0 text-ui text-content-body">{String.capitalize(message.topic)}</span>
                    <span class="w-44 shrink-0 truncate font-mono text-xs font-medium text-content-strong" title={message.event}>{message.event}</span>
                    <span class="min-w-0 grow basis-0 truncate font-mono text-xs text-content-muted">{payload_text(message)}</span>
                    <span
                      class="lucide-chevron-right size-4 text-content-faint group-aria-expanded/message:lucide-chevron-down group-aria-expanded/message:text-content-muted"
                      aria-hidden="true"
                    ></span>
                  </button>

                  <%!-- Lined up under the Data column. --%>
                  <div class="hidden flex-col gap-3 px-4 pt-1 pb-4 group-aria-expanded/message:flex sm:pl-144">
                    <div class="flex flex-wrap items-center justify-between gap-2">
                      <span class="text-xs text-content-muted">{payload_note(message)}</span>
                      <button
                        :if={!DeviceMessage.metadata_only?(message)}
                        id={"#{dom_id}-copy"}
                        type="button"
                        phx-hook="CopyToClipboard"
                        data-copy-value={message.payload}
                        class="flex h-6.5 cursor-pointer items-center gap-1.5 rounded border border-line-control bg-surface-raised px-2 text-xs font-medium text-content-body shadow-xs hover:bg-surface-muted"
                      >
                        <span data-icon="copy" class="lucide-copy size-3.25 text-content-muted" aria-hidden="true"></span>
                        <span data-icon="check" class="lucide-check hidden size-3.25 text-success-content" aria-hidden="true"></span> Copy
                      </button>
                    </div>
                    <div phx-no-format class="max-h-96 overflow-auto rounded-card border border-line-default bg-surface-raised px-3.5 py-3 font-mono text-xs/5 whitespace-pre text-content-body">{pretty_payload(message)}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div :if={@has_messages} class="flex min-h-14 flex-wrap items-center justify-center gap-3 px-4 py-3">
          <%!-- `data-count` changes with every page, which is what makes the
                hook see an update and check whether this is still on screen. --%>
          <.button
            :if={@more_messages and @message_count < max_messages()}
            id="show-more-messages"
            size="sm"
            phx-hook="LoadMoreOnVisible"
            data-event="load-more-messages"
            data-list="device-messages"
            data-count={@message_count}
            class="data-loading:opacity-50"
          >
            Show older messages
          </.button>
          <span :if={@more_messages and @message_count >= max_messages()} class="text-xs text-content-muted">
            Showing the newest {max_messages()} messages. Narrow by direction or channel to look further back.
          </span>
          <span class="text-xs text-content-faint">
            Payloads over {kilobytes(Payload.max_bytes())} are kept truncated; secrets are redacted
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp direction_label("sent"), do: "To device"
  defp direction_label(_received), do: "From device"

  defp payload_note(message) do
    cond do
      DeviceMessage.metadata_only?(message) ->
        "Only the size is recorded for terminal traffic"

      DeviceMessage.truncated?(message) ->
        "Truncated for storage · #{kilobytes(message.payload_bytes)} were sent, the first #{kilobytes(byte_size(message.payload))} kept"

      true ->
        "#{kilobytes(message.payload_bytes)}"
    end
  end

  # Laid out when it is JSON, which it is unless it was cut short for storage;
  # keys keep the order the device sent them in.
  defp pretty_payload(message) do
    with false <- DeviceMessage.metadata_only?(message),
         {:ok, decoded} <- Jason.decode(message.payload, objects: :ordered_objects),
         {:ok, pretty} <- Jason.encode(decoded, pretty: true) do
      pretty
    else
      _ -> payload_text(message)
    end
  end

  defp kilobytes(bytes) when bytes < 1024, do: bytes(bytes)
  defp kilobytes(bytes) when rem(bytes, 1024) == 0, do: "#{div(bytes, 1024)} KB"
  defp kilobytes(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"

  # Console and local shell rows carry a size and no contents, on purpose — see
  # `NervesHub.Devices.DeviceMessages` for why.
  defp payload_text(message) do
    if DeviceMessage.metadata_only?(message) do
      "#{bytes(message.payload_bytes)} (contents not recorded)"
    else
      message.payload
    end
  end

  defp bytes(1), do: "1 byte"
  defp bytes(count), do: "#{count} bytes"

  defp max_messages(), do: @max_messages

  defp direction_options() do
    [{"Both ways", "all"}, {"From device", "received"}, {"To device", "sent"}]
  end

  defp topic_options() do
    [{"All channels", "all"}, {"Device", "device"}, {"Console", "console"}, {"Extensions", "extensions"}]
  end
end
