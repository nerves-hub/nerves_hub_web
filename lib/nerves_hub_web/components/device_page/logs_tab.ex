defmodule NervesHubWeb.Components.DevicePage.LogsTab do
  use NervesHubWeb, tab_component: :logs

  alias NervesHub.Devices.LogLines

  alias Phoenix.LiveView.JS

  def tab_params(_params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> assign(:streaming_enabled, true)
      |> configure_stream()
      |> fetch_logs()
      |> cont()
    else
      socket
      |> assign(:analytics_enabled, false)
      |> assign(:streaming_enabled, false)
      |> cont()
    end
  end

  def cleanup() do
    [:has_logs, :log_inserted]
  end

  defp configure_stream(%{assigns: %{streams: %{log_lines: _}}} = socket) do
    socket
  end

  defp configure_stream(socket) do
    stream_configure(socket, :log_lines,
      dom_id: fn log_line ->
        timestamp =
          log_line.timestamp
          |> DateTime.to_string()
          |> String.replace(" ", "-")
          |> String.replace(":", "-")
          |> String.replace(".", "-")

        "log-line-#{timestamp}"
      end
    )
  end

  defp fetch_logs(socket, opts \\ []) do
    log_lines = LogLines.recent(socket.assigns.device)

    socket
    |> stream(:log_lines, log_lines, opts)
    |> assign(:has_logs, Enum.any?(log_lines))
    |> assign(:log_inserted, false)
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event("toggle_log_streaming", _, %{assigns: %{streaming_enabled: false}} = socket) do
    socket
    |> fetch_logs(reset: true)
    |> assign(:streaming_enabled, true)
    |> halt()
  end

  def hooked_event("toggle_log_streaming", _, %{assigns: %{streaming_enabled: true}} = socket) do
    socket
    |> assign(:streaming_enabled, false)
    |> halt()
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(
        %Broadcast{event: "logs:received", payload: log_line},
        %{assigns: %{streaming_enabled: true}} = socket
      ) do
    socket
    |> stream_insert(:log_lines, log_line, at: 0, limit: 25)
    |> assign(:log_inserted, true)
    |> assign(:has_logs, true)
    |> halt()
  end

  def hooked_info(
        %Broadcast{event: "logs:received"},
        %{assigns: %{streaming_enabled: false}} = socket
      ) do
    halt(socket)
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  def render(%{analytics_enabled: analytics_enabled} = assigns) when analytics_enabled == false do
    ~H"""
    <div class="size-full p-12">
      <div class="size-full flex flex-col justify-center items-center p-6 gap-6 text-medium font-mono">
        <div class="font-bold">Analytics aren't enabled for your platform.</div>
        <div>Check contact your Ops team for more information.</div>
      </div>
    </div>
    """
  end

  def render(%{product: %{extensions: %{logging: logging}}} = assigns) when logging == false do
    ~H"""
    <div class="size-full p-12">
      <div class="size-full flex flex-col justify-center items-center p-6 gap-6 text-medium font-mono">
        <div class="font-bold">Device logs aren't enabled for this product.</div>
        <div>Please check the product settings.</div>
      </div>
    </div>
    """
  end

  def render(%{device: %{extensions: %{logging: logging}}} = assigns) when logging == false do
    ~H"""
    <div class="size-full p-12">
      <div class="size-full flex flex-col justify-center items-center p-6 gap-6 text-medium font-mono">
        <div class="font-bold">Device logs aren't enabled.</div>
        <div>Please check the device settings.</div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="size-full bg-[#0e1019]">
      <div :if={!@has_logs} class="size-full flex justify-center items-center p-6 gap-6 text-medium font-mono">
        <div>No logs have been received yet.</div>
      </div>
      <div :if={@has_logs} class="flex flex-row items-center justify-between h-11 border-b border-zinc-700 px-12">
        <div>
          <span class="text-sm text-zinc-400">Live log streaming :</span>
          <button
            id="toggle-log-streaming"
            type="button"
            phx-click="toggle_log_streaming"
            class={[
              "relative inline-flex items-center h-3.5 w-6 shrink-0 cursor-pointer rounded-full border-1.5 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-0",
              (@streaming_enabled && "bg-emerald-500") || "bg-red-500"
            ]}
            role="switch"
            aria-checked="false"
          >
            <span
              aria-hidden="true"
              class={[
                "pointer-events-none inline-block size-3",
                (@streaming_enabled && "translate-x-3") || "translate-x-0",
                "transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              ]}
            >
            </span>
          </button>
        </div>
        <span class="text-sm text-zinc-400 font-extralight">Showing the last 25 log lines.</span>
      </div>
      <div :if={@has_logs} id="log_lines" phx-update="stream" class="flex flex-col size-full items-start gap-2 px-12 py-10">
        <div :for={{dom_id, line} <- @streams.log_lines} id={dom_id} phx-mounted={@log_inserted && fade_in()} class="flex flex-row gap-4 font-mono text-sm">
          <div id={"#{DateTime.to_unix(line.timestamp, :microsecond)}-log-line-localtime"} phx-hook="LogLineLocalTime" class="w-60">
            {line.timestamp}
          </div>
          <div
            data-log-level={line.level}
            class="w-24 data-[log-level=emergency]:text-red-500 data-[log-level=alert]:text-red-500 data-[log-level=critical]:text-red-500 data-[log-level=error]:text-red-500 data-[log-level=warn]:text-orange-500 data-[log-level=warning]:text-orange-500 data-[log-level=debug]:text-blue-500"
          >
            [{line.level}]
          </div>
          <div>{line.message}</div>
        </div>
      </div>
    </div>
    """
  end

  defp fade_in() do
    JS.transition(
      {"first:ease-in duration-500", "first:opacity-0 first:p-0 first:h-0", "first:opacity-100"},
      time: 3000,
      blocking: false
    )
  end
end
