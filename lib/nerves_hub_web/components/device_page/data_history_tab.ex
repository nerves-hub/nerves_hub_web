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
  """

  use NervesHubWeb, tab_component: :data_history

  alias NervesHub.Devices.DeviceMessage
  alias NervesHub.Devices.DeviceMessages

  @limit 100

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
    [:has_messages, :direction_filter, :topic_filter]
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

  defp fetch_messages(socket) do
    messages =
      DeviceMessages.recent(socket.assigns.device,
        limit: @limit,
        direction: query_filter(socket.assigns.direction_filter),
        topic: query_filter(socket.assigns.topic_filter)
      )

    socket
    |> stream(:messages, messages, reset: true)
    |> assign(:has_messages, Enum.any?(messages))
  end

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
      socket
      |> stream_insert(:messages, message, at: 0, limit: @limit)
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
    <div class="size-full p-12">
      <div class="text-medium flex size-full flex-col items-center justify-center gap-6 p-6 font-mono">
        <div class="font-bold">Analytics aren't enabled for your platform.</div>
        <div>Check contact your Ops team for more information.</div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id="data-history-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="bg-base-950 phx-click-loading:opacity-50 tab-content size-full pb-10 opacity-0 transition-all duration-500"
    >
      <div class="border-base-700 flex h-11 flex-row items-center justify-between border-b px-12">
        <div class="flex flex-row items-center gap-6">
          <div>
            <span class="text-base-400 text-sm">Live streaming :</span>
            <button
              id="toggle-message-streaming"
              type="button"
              phx-click="toggle-streaming"
              class={[
                "border-1.5 relative inline-flex h-3.5 w-6 shrink-0 cursor-pointer items-center rounded-full border-transparent transition-colors duration-200 ease-in-out focus:ring-0 focus:outline-none",
                (@streaming_enabled && "bg-success") || "bg-alert"
              ]}
              role="switch"
              aria-checked={to_string(@streaming_enabled)}
              aria-label="Toggle live streaming of device messages"
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

          <form id="data-history-filters" phx-change="filter-messages" class="flex flex-row items-center gap-4">
            <label class="flex items-center gap-2">
              <span class="text-base-400 text-sm">Direction :</span>
              <select name="direction" class="bg-base-800 border-base-600 text-base-300 rounded border px-2 py-0.5 text-sm">
                <option :for={{label, value} <- direction_options()} value={value} selected={value == @direction_filter}>
                  {label}
                </option>
              </select>
            </label>

            <label class="flex items-center gap-2">
              <span class="text-base-400 text-sm">Channel :</span>
              <select name="topic" class="bg-base-800 border-base-600 text-base-300 rounded border px-2 py-0.5 text-sm">
                <option :for={{label, value} <- topic_options()} value={value} selected={value == @topic_filter}>
                  {label}
                </option>
              </select>
            </label>
          </form>
        </div>

        <span class="text-base-400 text-sm font-extralight">
          {(@streaming_enabled && "Streaming the last #{limit()} messages.") || "Paused."}
        </span>
      </div>

      <div :if={!@has_messages} class="text-medium flex size-full items-center justify-center gap-6 p-6 font-mono">
        <div>No messages have been recorded yet.</div>
      </div>

      <div :if={@has_messages} class="scrollable-inner size-full overflow-x-auto px-12 pt-6">
        <table class="w-full table-fixed font-mono text-sm">
          <colgroup>
            <col class="w-52" />
            <col class="w-28" />
            <col class="w-28" />
            <col class="w-44" />
            <col />
          </colgroup>
          <thead>
            <tr class="border-base-700 text-base-400 border-b text-left font-extralight">
              <th class="py-2 pr-6 font-normal">Timestamp (UTC)</th>
              <th class="py-2 pr-6 font-normal">Direction</th>
              <th class="py-2 pr-6 font-normal">Channel</th>
              <th class="py-2 pr-6 font-normal">Event</th>
              <th class="py-2 font-normal">Data</th>
            </tr>
          </thead>
          <tbody id="device-messages" phx-update="stream">
            <tr :for={{dom_id, message} <- @streams.messages} id={dom_id} class="border-base-800 hover:bg-base-900 border-b align-top">
              <td class="text-base-300 py-2 pr-6 whitespace-nowrap">
                {Calendar.strftime(message.timestamp, "%Y-%m-%d %H:%M:%S")}
              </td>
              <td class="py-2 pr-6">
                <span class={[
                  "rounded px-1.5 py-0.5 text-xs",
                  (message.direction == "sent" && "bg-base-800 text-blue-400") || "bg-base-800 text-success"
                ]}>
                  {message.direction}
                </span>
              </td>
              <td class="text-base-400 py-2 pr-6">{message.topic}</td>
              <td class="text-base-200 truncate py-2 pr-6" title={message.event}>{message.event}</td>
              <td class="text-base-300 py-2">
                <div class="max-h-24 overflow-y-auto break-all whitespace-pre-wrap">{payload_text(message)}</div>
                <div :if={DeviceMessage.truncated?(message)} class="text-base-500 pt-1 text-xs">
                  truncated for storage — {bytes(message.payload_bytes)} were sent
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div class="h-10"></div>
      </div>
    </div>
    """
  end

  # Console rows carry a size and no contents, on purpose — see
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

  defp limit(), do: @limit

  defp direction_options() do
    [{"All", "all"}, {"Received from device", "received"}, {"Sent to device", "sent"}]
  end

  defp topic_options() do
    [{"All", "all"}, {"Device", "device"}, {"Console", "console"}, {"Extensions", "extensions"}]
  end
end
