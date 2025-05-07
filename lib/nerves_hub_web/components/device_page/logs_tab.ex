defmodule NervesHubWeb.Components.DevicePage.LogsTab do
  use NervesHubWeb, tab_component: :logs

  alias NervesHub.Devices.LogLines

  alias Phoenix.LiveView.JS

  def tab_params(_params, _uri, socket) do
    if analytics_enabled?() do
      socket
      |> configure_stream()
      |> fetch_logs()
      |> cont()
    else
      socket
      |> assign(:analytics_enabled, false)
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

  defp fetch_logs(socket) do
    log_lines = LogLines.recent(socket.assigns.device)

    socket
    |> stream(:log_lines, log_lines, [])
    |> assign(:has_logs, Enum.any?(log_lines))
    |> assign(:log_inserted, false)
  end

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_info(%Broadcast{event: "logs:received", payload: log_line}, socket) do
    socket
    |> stream_insert(:log_lines, log_line, at: 0, limit: 25)
    |> assign(:log_inserted, true)
    |> assign(:has_logs, true)
    |> halt()
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
    <div class="size-full p-12">
      <div :if={!@has_logs} class="size-full flex justify-center items-center p-6 gap-6 text-medium font-mono">
        <div>No logs have been received yet.</div>
      </div>
      <div :if={@has_logs} class="text-base italic font-medium pb-6">Showing the last 25 log lines.</div>
      <div :if={@has_logs} id="log_lines" phx-update="stream" class="flex flex-col size-full items-start gap-2">
        <div :for={{dom_id, line} <- @streams.log_lines} id={dom_id} phx-mounted={@log_inserted && fade_in()} class="flex flex-row gap-4 font-mono text-sm">
          <div id={"#{DateTime.to_unix(line.timestamp, :microsecond)}-log-line-localtime"} phx-hook="LogLineLocalTime">
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
