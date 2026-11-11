defmodule NervesHubWeb.Components.DevicePage.LocalShellTab do
  use NervesHubWeb, tab_component: :local_shell

  alias NervesHub.Consoles
  alias NervesHubWeb.Components.DevicePage.ConsoleTab
  alias NervesHubWeb.Components.DevicePage.TerminalFrame
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

  def render(assigns) do
    ~H"""
    <div
      id="local-shell-tab"
      phx-mounted={JS.remove_class("opacity-0")}
      class="tab-content size-full opacity-0 transition-all duration-500 phx-click-loading:opacity-50"
    >
      <.async_result :let={online?} assign={@local_shell_active?}>
        <:loading>
          <TerminalFrame.frame terminal_id="local-shell" status={:checking} identifier={@device.identifier}>
            <TerminalFrame.message :if={authorized?(:"device:extensions:local_shell", @current_scope)}>
              Checking if the device's local shell is available…
            </TerminalFrame.message>
          </TerminalFrame.frame>
        </:loading>
        <:failed :let={_failure}>
          <TerminalFrame.frame terminal_id="local-shell" status={:unavailable} identifier={@device.identifier}>
            <TerminalFrame.message>There was an error checking if the device was online.</TerminalFrame.message>
          </TerminalFrame.frame>
        </:failed>
        <TerminalFrame.frame
          terminal_id="local-shell"
          status={if(@shell_enabled? and authorized?(:"device:extensions:local_shell", @current_scope) and online?, do: :connected, else: :unavailable)}
          identifier={@device.identifier}
          note="Shared session · everyone on this tab sees the same shell"
        >
          <div
            :if={@shell_enabled? and authorized?(:"device:extensions:local_shell", @current_scope) and online?}
            id="local-shell"
            phx-hook="LocalShell"
            phx-update="ignore"
            data-device-identifier={@device.identifier}
            class="z-10 size-full"
          >
          </div>
          <TerminalFrame.message :if={not @shell_enabled?}>
            <p>The device local shell isn't currently enabled.</p>
            <p>Please check your device and product settings to ensure that the local shell is enabled.</p>
          </TerminalFrame.message>
          <TerminalFrame.message :if={@shell_enabled? and authorized?(:"device:extensions:local_shell", @current_scope) and not online?}>
            The device's local shell isn't currently available.
          </TerminalFrame.message>
          <TerminalFrame.message :if={not authorized?(:"device:extensions:local_shell", @current_scope)} tone={:alert}>
            You don't have the required permissions to access a local shell on the Device.
          </TerminalFrame.message>
        </TerminalFrame.frame>
      </.async_result>
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
