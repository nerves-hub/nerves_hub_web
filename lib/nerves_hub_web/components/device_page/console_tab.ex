defmodule NervesHubWeb.Components.DevicePage.ConsoleTab do
  use NervesHubWeb, tab_component: :console

  alias NervesHub.Consoles
  alias NervesHubWeb.Components.DevicePage.TerminalFrame
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  # How long to wait for the device's console channel to answer a locate before
  # saying there isn't one. It answers in milliseconds when it exists, so this
  # only bounds how long a console that isn't there takes to say so.
  @locate_timeout to_timeout(second: 1)

  def tab_params(_params, _uri, socket) do
    socket
    |> seed_console_active()
    |> locate_console()
    |> cont()
  end

  # Coming back from another tab starts from a fresh seed. Kept, the last value
  # could show a terminal for a console that went away while we were elsewhere.
  def cleanup(), do: [:console_active?]

  @doc """
  Stop watching the console, for the local shell tab to call when it takes over.

  The monitor outlives a switch to another tab, because both run in the same
  LiveView process. It would do no harm (the LiveView ignores a `:DOWN` it has no
  hook for, and coming back to this tab locates afresh), but it would wake the
  process for a tab nobody is looking at.
  """
  def release_console(socket) do
    if ref = socket.assigns[:console_monitor], do: Process.demonitor(ref, [:flush])

    assign(socket, console_monitor: nil, console_locate: nil)
  end

  # The device-side console channel joined: the device connected, or came back.
  def hooked_info(%Broadcast{event: "console_joined"}, socket) do
    socket
    |> locate_console()
    |> halt()
  end

  def hooked_info({:console_located, ref, console}, %{assigns: %{console_locate: ref}} = socket) do
    socket
    |> release_console()
    |> assign(:console_monitor, Process.monitor(console))
    |> put_console_active(true)
    |> halt()
  end

  # An answer to an earlier locate, or a second console channel answering the
  # same one. The first answer to the latest locate is the one we watch.
  def hooked_info({:console_located, _ref, _console}, socket), do: halt(socket)

  def hooked_info({:console_locate_timeout, ref}, %{assigns: %{console_locate: ref}} = socket) do
    socket
    |> release_console()
    |> put_console_active(false)
    |> halt()
  end

  def hooked_info({:console_locate_timeout, _ref}, socket), do: halt(socket)

  # The console channel went away. Look again rather than reporting it gone
  # straight off: a device that reconnected may already have another one.
  def hooked_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{console_monitor: ref}} = socket) do
    socket
    |> assign(:console_monitor, nil)
    |> locate_console()
    |> halt()
  end

  def hooked_info(%Broadcast{event: "file-data/start", payload: payload}, socket) do
    if socket.assigns.user.id == payload.uploaded_by do
      put_flash(socket, :info, "Upload started.")
    else
      socket
    end
    |> halt()
  end

  def hooked_info(%Broadcast{event: "file-data/stop", payload: payload}, socket) do
    if socket.assigns.user.id == payload.uploaded_by do
      put_flash(socket, :info, "Upload finished.")
    else
      socket
    end
    |> halt()
  end

  def hooked_info(_event, socket), do: {:cont, socket}

  # Only when the tab opens. While it stays open the indicator keeps what it last
  # knew during a new locate, so locating again never takes an open terminal off
  # the page.
  defp seed_console_active(%{assigns: %{console_active?: _}} = socket), do: socket

  defp seed_console_active(socket) do
    # An offline device has no console to find, so say so now rather than after
    # the timeout. The locate still runs, in case the connection row is behind.
    seed =
      case socket.assigns.device_connection do
        %{status: status} when status in [:connecting, :connected] -> AsyncResult.loading()
        _ -> AsyncResult.ok(false)
      end

    assign(socket, :console_active?, seed)
  end

  # Answered by `{:console_located, ref, console}` from the console channel, if
  # there is one, or by our own `{:console_locate_timeout, ref}` if not. Only the
  # latest locate's answer counts. Skipped on the disconnected render, which has
  # no process to answer.
  defp locate_console(socket) do
    if connected?(socket) do
      ref = Consoles.PubSub.locate_console(socket.assigns.device.id)
      _ = Process.send_after(self(), {:console_locate_timeout, ref}, @locate_timeout)

      assign(socket, :console_locate, ref)
    else
      socket
    end
  end

  defp put_console_active(socket, active?) do
    assign(socket, :console_active?, AsyncResult.ok(socket.assigns.console_active?, active?))
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def render(assigns) do
    ~H"""
    <div
      id="console-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content size-full opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <.async_result :let={online?} assign={@console_active?}>
        <:loading>
          <TerminalFrame.frame terminal_id="console" name="Console" status={:checking} identifier={@device.identifier}>
            <TerminalFrame.message :if={authorized?(:"device:console", @current_scope)}>
              Checking if the device is online…
            </TerminalFrame.message>
          </TerminalFrame.frame>
        </:loading>
        <:failed :let={_failure}>
          <TerminalFrame.frame terminal_id="console" name="Console" status={:unavailable} identifier={@device.identifier}>
            <TerminalFrame.message>There was an error checking if the device was online.</TerminalFrame.message>
          </TerminalFrame.frame>
        </:failed>
        <TerminalFrame.frame
          terminal_id="console"
          name="Console"
          file_input="console-file"
          status={if(authorized?(:"device:console", @current_scope) && online?, do: :connected, else: :unavailable)}
          identifier={@device.identifier}
          note="Shared session · everyone on this tab sees the same console"
          hint="Drop a file on the console to send it to the device"
        >
          <div :if={authorized?(:"device:console", @current_scope) && online?} id="console" phx-hook="Console" phx-update="ignore" data-device-identifier={@device.identifier} class="z-10 size-full"></div>
          <TerminalFrame.message :if={authorized?(:"device:console", @current_scope) && !online?}>
            The device console isn't currently available.
          </TerminalFrame.message>
          <TerminalFrame.message :if={!authorized?(:"device:console", @current_scope)} tone={:alert}>
            You don't have the required permissions to access a Device console.
          </TerminalFrame.message>
        </TerminalFrame.frame>
      </.async_result>
    </div>
    """
  end
end
