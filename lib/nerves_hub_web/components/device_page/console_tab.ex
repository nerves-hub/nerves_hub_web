defmodule NervesHubWeb.Components.DevicePage.ConsoleTab do
  use NervesHubWeb, tab_component: :console

  alias NervesHub.Consoles
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

  def toggle_fullscreen(js \\ %JS{}) do
    js
    # Dropzone
    # disable relative
    |> JS.toggle_class("relative", to: "#dropzone")
    |> JS.toggle_class("fixed", to: "#dropzone")
    |> JS.toggle_class("top-0", to: "#dropzone")
    |> JS.toggle_class("left-0", to: "#dropzone")
    |> JS.toggle_class("right-0", to: "#dropzone")
    |> JS.toggle_class("bottom-0", to: "#dropzone")
    # disable p-12
    |> JS.toggle_class("p-12", to: "#dropzone")
    |> JS.toggle_class("p-6", to: "#dropzone")
    |> JS.toggle_class("pt-14", to: "#dropzone")
    |> JS.toggle_class("pb-4", to: "#dropzone")
    |> JS.toggle_class("box-border", to: "#dropzone")

    # Immersive device information
    |> JS.toggle(to: "#immersive-device")

    # Console
    |> JS.toggle_class("box-border", to: "#console")
    # disable w-full
    |> JS.toggle_class("w-full", to: "#console")
    # disable h-full
    |> JS.toggle_class("h-full", to: "#console")

    # Terminal controls (the option-as-meta toggle and the fullscreen/close button)
    # disable right-16
    |> JS.toggle_class("right-16", to: "#terminal-controls")
    |> JS.toggle_class("right-4", to: "#terminal-controls")
    # disable top-8
    |> JS.toggle_class("top-8", to: "#terminal-controls")
    |> JS.toggle_class("top-4", to: "#terminal-controls")
    |> JS.toggle_class("hidden", to: "#fullscreen svg")
  end

  def render(assigns) do
    token = Phoenix.Token.sign(NervesHubWeb.Endpoint, "user salt", assigns.user.id)

    assigns = Map.put(assigns, :user_token, token)

    ~H"""
    <div
      id="console-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content size-full opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <div class="flex size-full flex-col items-start justify-between">
        <.async_result :let={online?} assign={@console_active?}>
          <:loading>
            <div class="flex size-full bg-black" style="background-color: rgb(14, 16, 25);">
              <div :if={authorized?(:"device:console", @current_scope)} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono">
                Checking if the device is online...
              </div>
            </div>
          </:loading>
          <:failed :let={_failure}>
            <div class="flex size-full bg-black" style="background-color: rgb(14, 16, 25);">
              <div class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono">
                There was an error checking if the device was online.
              </div>
            </div>
          </:failed>
          <div id="console-and-chat" class="flex size-full bg-black" style="background-color: rgb(14, 16, 25);">
            <div :if={authorized?(:"device:console", @current_scope) && online?} id="dropzone" class="relative flex grow gap-6 p-12" style="background-color: rgb(14, 16, 25);">
              <div id="console" phx-hook="Console" phx-update="ignore" data-user-token={@user_token} data-device-identifier={@device.identifier} class="z-10 size-full"></div>
              <div id="immersive-device" class="pointer-events-none absolute top-4 left-6 z-20 hidden text-base-800">
                <div class="flex items-center gap-3">
                  <%= if Map.get(@device_connection || %{}, :status) == :connected do %>
                    <svg class="size-3" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 6" fill="none">
                      <circle cx="3" cy="3" r="3" fill="#10B981" />
                    </svg>
                  <% else %>
                    <svg class="size-3" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 6 6" fill="none">
                      <circle cx="3" cy="3" r="3" fill="#71717A" />
                    </svg>
                  <% end %>
                  <h1 class="font-mono text-xl leading-[30px] font-semibold text-base-50">
                    {@device.identifier}
                  </h1>
                </div>
              </div>
              <div id="terminal-controls" phx-update="ignore" class="absolute top-8 right-16 z-20 flex items-center gap-3">
                <label
                  class="hidden cursor-pointer items-center gap-2 rounded-full bg-neutral-900 px-3 py-1.5 text-xs text-neutral-50"
                  title="Send ⌥ (Option) to the device as Meta, for shortcuts such as M-b and M-f. Leave this off to type characters like [ ] { } | on non-US keyboard layouts."
                >
                  <input type="checkbox" id="option-as-meta" class="size-3.5 rounded border-base-700 text-base-400 checked:bg-primary focus:ring-0" />
                  <span>⌥ as Meta</span>
                </label>
                <button id="fullscreen" class="cursor-pointer rounded-full bg-neutral-900 hover:scale-[1.1]" phx-click={toggle_fullscreen()} title="Toggle fullscreen">
                  <svg class="stroke-neutral-50" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M15 19H19M19 19V15M19 19L15 15M9 5H5M5 5V9M5 5L9 9M15 5H19M19 5V9M19 5L15 9M9 19H5M5 19V15M5 19L9 15" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <svg class="hidden stroke-neutral-50" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M12 12L7 7M12 12L17 17M12 12L17 7M12 12L7 17" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>
              </div>
            </div>
            <div :if={authorized?(:"device:console", @current_scope) && !online?} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono">
              The device console isn't currently available.
            </div>
            <div :if={!authorized?(:"device:console", @current_scope)} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono text-alert">
              You don't have the required permissions to access a Device console.
            </div>
          </div>
        </.async_result>
      </div>
    </div>
    """
  end
end
