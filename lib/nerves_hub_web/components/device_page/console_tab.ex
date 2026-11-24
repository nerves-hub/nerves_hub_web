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

  @decorate requires_membership()
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
          <.upload_dialog :if={authorized?(:"device:console", @current_scope) && online?} platform={NervesHub.Branding.friendly_platform_name()} />
          <TerminalFrame.message :if={authorized?(:"device:console", @current_scope) && !online?}>
            The device console isn't currently available.
          </TerminalFrame.message>
          <TerminalFrame.message :if={!authorized?(:"device:console", @current_scope)} tone={:alert}>
            You don't have the required permissions to access a Device console.
          </TerminalFrame.message>
          <:footer :if={authorized?(:"device:console", @current_scope) && online?}>
            <.upload_strip platform={NervesHub.Branding.friendly_platform_name()} />
          </:footer>
        </TerminalFrame.frame>
      </.async_result>
    </div>
    """
  end

  # How a file sent to the device is going, for whoever sent it.
  # `assets/js/helpers/consoleUploadView.js` shows these and fills them in,
  # setting `data-state` to uploading, saving, saved or failed, `data-step` on
  # each step, and `data-acks` when the device reports each chunk it saves.
  # Every state's words are here, and the state picks which show. Both are
  # ignored by patches, which would otherwise put back what the script changed.
  #
  # The dialog lies over the terminal. It opens if the file takes more than a
  # moment, and Hide leaves the strip under the terminal instead.
  attr(:platform, :string, required: true)

  defp upload_dialog(assigns) do
    ~H"""
    <div id="console-upload" phx-update="ignore" class="contents">
      <div data-upload-dialog data-state="uploading" hidden class="group/upload absolute inset-0 z-20">
        <div class="flex size-full items-end justify-center bg-backdrop sm:items-center sm:p-4">
          <div
            role="dialog"
            aria-labelledby="console-upload-title"
            aria-describedby="console-upload-note"
            tabindex="-1"
            class="max-h-full w-full overflow-y-auto rounded-t-xl border-t border-line-default bg-surface-overlay font-sans shadow-overlay sm:max-w-110 sm:rounded-md sm:border"
          >
            <div class="flex justify-center pt-2 pb-1 sm:hidden" aria-hidden="true">
              <span class="h-1 w-9 rounded-full bg-line-default"></span>
            </div>

            <div class="flex items-start gap-3 px-4 pt-3 sm:px-5 sm:pt-5">
              <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-content-body group-data-[state=failed]/upload:bg-alert-soft group-data-[state=failed]/upload:text-alert-content group-data-[state=saved]/upload:bg-success-soft group-data-[state=saved]/upload:text-success-content">
                <span class="lucide-upload size-4 group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden" aria-hidden="true"></span>
                <span class="lucide-circle-check hidden size-4 group-data-[state=saved]/upload:block" aria-hidden="true"></span>
                <span class="lucide-circle-exclamation-point hidden size-4 group-data-[state=failed]/upload:block" aria-hidden="true"></span>
              </span>
              <div class="flex min-w-0 flex-1 flex-col gap-1">
                <h2 id="console-upload-title" class="text-card-title font-semibold text-content-strong">
                  <span class="group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden">Sending a file to the device</span>
                  <span class="hidden group-data-[state=saved]/upload:inline">Saved on the device</span>
                  <span class="hidden group-data-[state=failed]/upload:inline">The file wasn't saved</span>
                </h2>
                <p class="truncate text-ui/5 text-content-muted">
                  <span data-upload-field="name" class="font-mono font-medium text-content-strong"></span> · <span data-upload-field="size"></span><span data-upload-field="count"></span>
                </p>
              </div>
            </div>

            <ol class="flex flex-col gap-4 px-4 pt-5 sm:px-5">
              <li data-upload-step="upload" data-step="active" class="group/step flex gap-3">
                <.step_marker />
                <div class="flex min-w-0 flex-1 flex-col gap-2">
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-ui/4.5 font-medium text-content-strong group-data-[step=done]/step:font-normal group-data-[step=done]/step:text-content-muted">
                      <span class="group-data-[step=done]/step:hidden">Upload to {@platform}</span>
                      <span class="hidden group-data-[step=done]/step:inline">Uploaded to {@platform}</span>
                    </span>
                    <span class="shrink-0 font-mono text-xs text-content-muted">
                      <span data-upload-field="sent" class="hidden group-data-[step=active]/step:inline"></span>
                      <span data-upload-field="uploaded-in" class="hidden group-data-[step=done]/step:inline"></span>
                    </span>
                  </div>
                  <div class="hidden h-1 overflow-hidden rounded-full bg-base-800 group-data-[step=active]/step:block">
                    <div data-upload-bar="sent" class="h-full w-0 rounded-full bg-success transition-[width] duration-200"></div>
                  </div>
                  <p data-upload-field="reason" class="hidden text-xs/4 text-alert-content group-data-[step=failed]/step:block"></p>
                </div>
              </li>
              <li data-upload-step="save" data-step="todo" class="group/step flex gap-3">
                <.step_marker />
                <div class="flex min-w-0 flex-1 flex-col gap-2">
                  <div class="flex items-center justify-between gap-3">
                    <span class="text-ui/4.5 text-content-muted group-data-[step=active]/step:font-medium group-data-[step=active]/step:text-content-strong group-data-[step=failed]/step:font-medium group-data-[step=failed]/step:text-content-strong">
                      <span class="group-data-[step=done]/step:hidden">Device receives and saves it</span>
                      <span class="hidden group-data-[step=done]/step:inline">Device received and saved it</span>
                    </span>
                    <span class="shrink-0 font-mono text-xs text-content-muted">
                      <span class="hidden font-sans text-content-faint group-data-[step=todo]/step:inline">Next</span>
                      <span data-upload-field="clock" class="hidden group-data-[step=active]/step:inline"></span>
                      <span data-upload-field="saved-in" class="hidden group-data-[step=done]/step:inline"></span>
                    </span>
                  </div>
                  <div class="hidden h-1 overflow-hidden rounded-full bg-base-800 group-data-[step=active]/step:block">
                    <div class="h-full w-2/5 animate-progress-slide rounded-full bg-success group-data-acks/upload:hidden motion-reduce:w-full motion-reduce:animate-none"></div>
                    <div data-upload-bar="saved" class="hidden h-full w-0 rounded-full bg-success transition-[width] duration-200 group-data-acks/upload:block"></div>
                  </div>
                  <p class="hidden text-xs/4 text-content-muted group-data-[step=active]/step:block">
                    <span class="group-data-acks/upload:hidden">The device doesn't report progress, so this ends when its console answers again.</span>
                    <span class="hidden group-data-acks/upload:inline"><span data-upload-field="saved"></span> saved</span>
                  </p>
                  <p data-upload-field="reason" class="hidden text-xs/4 text-alert-content group-data-[step=failed]/step:block"></p>
                </div>
              </li>
            </ol>

            <div
              id="console-upload-note"
              class="mx-4 mt-5 flex gap-2.5 rounded-card bg-surface-muted px-3.5 py-3 group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden sm:mx-5"
            >
              <span class="mt-0.5 lucide-info size-4 text-content-muted" aria-hidden="true"></span>
              <div class="flex flex-col gap-1.5 text-ui/4.5">
                <p class="text-content-body">
                  The console doesn't answer while the device saves a file. Anything you type is kept and runs once it's saved.
                </p>
                <p class="text-content-muted">A large file over a slow connection can take a few minutes.</p>
              </div>
            </div>

            <div class="mt-5 flex items-center gap-2 border-line-subtle max-sm:flex-col max-sm:items-stretch max-sm:px-4 max-sm:pb-6 sm:border-t sm:px-5 sm:py-3">
              <p class="text-xs/4 text-content-muted max-sm:order-last max-sm:text-center">
                <span class="group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden">Hiding this keeps the progress under the console.</span>
                <span class="hidden group-data-[state=saved]/upload:inline">You can type in the console again.</span>
              </p>
              <div class="ml-auto flex justify-end max-sm:ml-0 max-sm:*:h-10 max-sm:*:w-full max-sm:*:rounded-md max-sm:*:text-sm">
                <span class="contents group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden">
                  <.button data-upload-action="hide">Hide</.button>
                </span>
                <span class="hidden group-data-[state=failed]/upload:contents group-data-[state=saved]/upload:contents">
                  <.button style="primary" data-upload-action="close">Back to the console</.button>
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # A step's marker, drawn from the `data-step` of the step it's in: an empty
  # ring before it starts, a dot while it's under way, a tick once it's done
  # and a cross if it failed.
  defp step_marker(assigns) do
    ~H"""
    <span
      aria-hidden="true"
      class="mt-px flex size-4.5 shrink-0 items-center justify-center rounded-full border-[1.5px] border-line-strong group-data-[step=active]/step:border-success group-data-[step=done]/step:border-success group-data-[step=done]/step:bg-success group-data-[step=failed]/step:border-alert group-data-[step=failed]/step:bg-alert"
    >
      <span class="hidden size-2 rounded-full bg-success group-data-[step=active]/step:block"></span>
      <span class="lucide-check--bold hidden size-3 text-white group-data-[step=done]/step:block"></span>
      <span class="lucide-x--bold hidden size-3 text-white group-data-[step=failed]/step:block"></span>
    </span>
    """
  end

  attr(:platform, :string, required: true)

  defp upload_strip(assigns) do
    ~H"""
    <div id="console-upload-strip" phx-update="ignore">
      <div data-upload-strip data-state="uploading" hidden class="group/upload">
        <div class="flex min-h-11 flex-wrap items-center gap-x-2.5 gap-y-2 border-t border-white/10 px-3.5 py-2.5 font-sans text-xs text-neutral-400">
          <span class="lucide-file size-4 text-neutral-400 group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden" aria-hidden="true"></span>
          <span class="lucide-circle-check hidden size-4 text-emerald-400 group-data-[state=saved]/upload:block" aria-hidden="true"></span>
          <span class="lucide-circle-exclamation-point hidden size-4 text-red-300 group-data-[state=failed]/upload:block" aria-hidden="true"></span>
          <span data-upload-field="name" class="max-w-48 truncate font-mono font-medium text-neutral-200"></span>
          <span role="status" class="min-w-60 flex-1">
            <span class="hidden group-data-[state=uploading]/upload:inline">Uploading to {@platform}</span>
            <span class="hidden group-data-[state=saving]/upload:inline">Saving on the device. Anything you type runs once it's saved.</span>
            <span class="hidden group-data-[state=saved]/upload:inline">Saved on the device. You can type again.</span>
            <span data-upload-field="reason" class="hidden group-data-[state=failed]/upload:inline"></span>
          </span>
          <div class="ml-auto flex items-center gap-3">
            <div class="hidden h-1 w-40 overflow-hidden rounded-full bg-white/10 group-data-[state=uploading]/upload:block max-sm:w-24">
              <div data-upload-bar="sent" class="h-full w-0 rounded-full bg-emerald-400 transition-[width] duration-200"></div>
            </div>
            <div class="hidden h-1 w-40 overflow-hidden rounded-full bg-white/10 group-data-[state=saving]/upload:block max-sm:w-24">
              <div class="h-full w-2/5 animate-progress-slide rounded-full bg-emerald-400 group-data-acks/upload:hidden motion-reduce:w-full motion-reduce:animate-none"></div>
              <div data-upload-bar="saved" class="hidden h-full w-0 rounded-full bg-emerald-400 transition-[width] duration-200 group-data-acks/upload:block"></div>
            </div>
            <span class="font-mono whitespace-nowrap text-neutral-400">
              <span data-upload-field="sent" class="hidden group-data-[state=uploading]/upload:inline"></span>
              <span data-upload-field="clock" class="hidden group-data-[state=saving]/upload:inline"></span>
              <span data-upload-field="total-in" class="hidden group-data-[state=saved]/upload:inline"></span>
            </span>
            <button
              type="button"
              data-upload-action="open"
              class="cursor-pointer rounded px-1.5 py-0.5 text-neutral-300 group-data-[state=failed]/upload:hidden group-data-[state=saved]/upload:hidden hover:bg-white/10 hover:text-white"
            >
              Details
            </button>
            <button
              type="button"
              data-upload-action="dismiss"
              aria-label="Dismiss"
              class="hidden size-6 cursor-pointer items-center justify-center rounded text-neutral-400 group-data-[state=failed]/upload:flex group-data-[state=saved]/upload:flex hover:bg-white/10 hover:text-white"
            >
              <span class="lucide-x size-3.5" aria-hidden="true"></span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
