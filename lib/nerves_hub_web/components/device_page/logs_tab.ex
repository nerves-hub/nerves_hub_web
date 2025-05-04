defmodule NervesHubWeb.Components.DevicePage.LogsTab do
  use NervesHubWeb, tab_component: :logs

  alias NervesHub.Devices.LogLines

  alias Phoenix.LiveView.JS

  def tab_params(_params, _uri, socket) do
    socket
    |> configure_stream()
    |> fetch_logs()
    |> cont()
  end

  def cleanup() do
    [:has_logs, :log_inserted]
  end

  defp configure_stream(%{assigns: %{streams: %{log_lines: _}}} = socket) do
    socket
  end

  defp configure_stream(socket) do
    stream_configure(socket, :log_lines, dom_id: &"log-line-#{&1.id}")
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

  def render(assigns) do
    ~H"""
    <div class="size-full p-12">
      <div :if={!@has_logs} class="size-full flex justify-center items-center p-6 gap-6 text-medium font-mono">
        <div>No logs have been received yet.</div>
      </div>
      <div :if={@has_logs} class="text-base italic font-medium pb-6">Showing the last 25 log lines.</div>
      <div :if={@has_logs} id="log_lines" phx-update="stream" class="flex flex-col size-full items-start gap-2">
        <div :for={{dom_id, line} <- @streams.log_lines} id={dom_id} phx-mounted={@log_inserted && fade_in()} class="flex flex-row gap-4 font-mono text-sm">
          <div>{line.logged_at |> NaiveDateTime.truncate(:second)}Z</div>
          <div
            data-log-level={line.level}
            class="data-[log-level=emergency]:text-red-500 data-[log-level=alert]:text-red-500 data-[log-level=critical]:text-red-500 data-[log-level=error]:text-red-500 data-[log-level=warn]:text-orange-500 data-[log-level=warning]:text-orange-500 data-[log-level=debug]:text-blue-500"
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
      time: 5000
    )
  end
end
