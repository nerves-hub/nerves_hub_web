defmodule NervesHubWeb.Components.DevicePage.LocalShellTab do
  use NervesHubWeb, tab_component: :local_shell

  alias NervesHub.Consoles
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  # How long to wait for an attached shell to answer a locate before saying
  # there isn't one. See `NervesHubWeb.Components.DevicePage.ConsoleTab`.
  @locate_timeout to_timeout(second: 1)

  def tab_params(_params, _uri, socket) do
    %{device: device, product: product} = socket.assigns

    enabled? = !!device.extensions.local_shell && !!product.extensions.local_shell

    # Only one of the two terminal tabs is hooked at a time, so release the
    # other's monitor rather than leaving it waking us for a tab we are not
    # rendering.
    socket = ConsoleTab.release_console(socket)

    socket
    |> assign(:shell_enabled?, enabled?)
    |> seed_local_shell_active()
    |> locate_local_shell()
    |> cont()
  end

  # Coming back from another tab starts from a fresh seed, as the console tab
  # does.
  def cleanup(), do: [:local_shell_active?]

  # The extension reports the shell attaching and detaching to the device page.
  # Either one settles the question, so a locate still in flight is moot.
  def hooked_info(%Broadcast{event: "local_shell_attached"}, socket) do
    socket
    |> assign(:local_shell_locate, nil)
    |> put_local_shell_active(true)
    |> halt()
  end

  def hooked_info(%Broadcast{event: "local_shell_detached"}, socket) do
    socket
    |> assign(:local_shell_locate, nil)
    |> put_local_shell_active(false)
    |> halt()
  end

  # A device that disconnects takes its shell with it, and no detach is sent on
  # the way out. The device page handles the event too, so it carries on.
  def hooked_info(%Broadcast{event: "connection:change", payload: %{status: "offline"}}, socket) do
    socket
    |> assign(:local_shell_locate, nil)
    |> put_local_shell_active(false)
    |> cont()
  end

  def hooked_info({:local_shell_located, ref}, %{assigns: %{local_shell_locate: ref}} = socket) do
    socket
    |> assign(:local_shell_locate, nil)
    |> put_local_shell_active(true)
    |> halt()
  end

  # An answer to an earlier locate, or one an event has already settled.
  def hooked_info({:local_shell_located, _ref}, socket), do: halt(socket)

  def hooked_info({:local_shell_locate_timeout, ref}, %{assigns: %{local_shell_locate: ref}} = socket) do
    socket
    |> assign(:local_shell_locate, nil)
    |> put_local_shell_active(false)
    |> halt()
  end

  def hooked_info({:local_shell_locate_timeout, _ref}, socket), do: halt(socket)

  def hooked_info(_event, socket), do: {:cont, socket}

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_async(_name, _async_fun_result, socket), do: {:cont, socket}

  def toggle_shell_fullscreen(js \\ %JS{}) do
    js
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
    |> JS.toggle_class("box-border", to: "#local-shell")
    # disable w-full
    |> JS.toggle_class("w-full", to: "#local-shell")
    # disable h-full
    |> JS.toggle_class("h-full", to: "#local-shell")

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
      id="local-shell-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content size-full opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <div class="flex size-full flex-col items-start justify-between">
        <.async_result :let={online?} assign={@local_shell_active?}>
          <:loading>
            <div class="flex size-full bg-black" style="background-color: rgb(14, 16, 25);">
              <div :if={authorized?(:"device:extensions:local_shell", @current_scope)} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono">
                Checking if the device's local shell is available...
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
          <div id="local-shell-wrapper" class="flex size-full bg-black" style="background-color: rgb(14, 16, 25);">
            <div
              :if={@shell_enabled? and authorized?(:"device:extensions:local_shell", @current_scope) and online?}
              id="dropzone"
              class="relative flex grow gap-6 p-12"
              style="background-color: rgb(14, 16, 25);"
            >
              <div id="local-shell" phx-hook="LocalShell" phx-update="ignore" data-user-token={@user_token} data-device-identifier={@device.identifier} class="z-10 size-full"></div>
              <div id="immersive-device" class="pointer-events-none absolute top-4 left-6 z-20 hidden text-base-800">
                <div class="flex items-center gap-3">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 6 6"
                    fill="currentColor"
                    class="size-3 data-[connection-status=connected]:fill-success data-[connection-status=connecting]:animate-pulse data-[connection-status=connecting]:fill-alert data-[connection-status=disconnected]:fill-base-500 data-[connection-status=unknown]:fill-base-500"
                    data-connection-status={Map.get(@device_connection || %{}, :status) || "unknown"}
                  >
                    <circle cx="3" cy="3" r="3" />
                  </svg>
                  <h1 class="font-mono text-xl leading-[30px] font-semibold text-base-50">
                    System Shell : {@device.identifier}
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
                <button id="fullscreen" class="cursor-pointer rounded-full bg-neutral-900 hover:scale-[1.1]" phx-click={toggle_shell_fullscreen()} title="Toggle fullscreen">
                  <svg class="stroke-neutral-50" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M15 19H19M19 19V15M19 19L15 15M9 5H5M5 5V9M5 5L9 9M15 5H19M19 5V9M19 5L15 9M9 19H5M5 19V15M5 19L9 15" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <svg class="hidden stroke-neutral-50" width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M12 12L7 7M12 12L17 17M12 12L17 7M12 12L7 17" stroke-width="1" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>
              </div>
            </div>
            <div :if={not @shell_enabled?} class="text-medium flex grow flex-col items-center justify-center gap-6 p-6 font-mono">
              <p>The device local shell isn't currently enabled.</p>
              <p>Please check your device and product settings to ensure that the local shell is enabled.</p>
            </div>
            <div :if={@shell_enabled? and authorized?(:"device:extensions:local_shell", @current_scope) and not online?} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono">
              The device's local shell isn't currently available.
            </div>
            <div :if={not authorized?(:"device:extensions:local_shell", @current_scope)} class="text-medium flex grow items-center justify-center gap-6 p-6 font-mono text-alert">
              You don't have the required permissions to access a local shell on the Device.
            </div>
          </div>
        </.async_result>
      </div>
    </div>
    """
  end

  # Only when the tab opens; see the console tab's `seed_console_active/1`.
  defp seed_local_shell_active(%{assigns: %{local_shell_active?: _}} = socket), do: socket

  defp seed_local_shell_active(socket) do
    seed =
      case socket.assigns do
        %{shell_enabled?: true, device_connection: %{status: status}} when status in [:connecting, :connected] ->
          AsyncResult.loading()

        _ ->
          AsyncResult.ok(false)
      end

    assign(socket, :local_shell_active?, seed)
  end

  # Answered by `{:local_shell_located, ref}` from an attached shell, or by our
  # own `{:local_shell_locate_timeout, ref}` if there is none. Skipped when the
  # shell is switched off, and on the disconnected render, which has no process
  # to answer.
  defp locate_local_shell(%{assigns: %{shell_enabled?: true}} = socket) do
    if connected?(socket) do
      ref = Consoles.PubSub.locate_local_shell(socket.assigns.device.id)
      _ = Process.send_after(self(), {:local_shell_locate_timeout, ref}, @locate_timeout)

      assign(socket, :local_shell_locate, ref)
    else
      socket
    end
  end

  defp locate_local_shell(socket), do: socket

  defp put_local_shell_active(socket, active?) do
    assign(socket, :local_shell_active?, AsyncResult.ok(socket.assigns.local_shell_active?, active?))
  end
end
