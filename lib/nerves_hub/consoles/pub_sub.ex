defmodule NervesHub.Consoles.PubSub do
  @moduledoc """
  Targeted pub/sub for remote terminal access — the device console and the
  local shell extension — backed by the `:group` library.

  This replaces the `Phoenix.PubSub` / `Phoenix.Channel` broadcasts that
  previously carried console and local-shell traffic. `Phoenix.PubSub` fans
  every message out to the pub/sub server on *every* node and filters locally;
  a device's terminal I/O is only ever consumed on the handful of web nodes
  holding the paired user channel (plus the one device node holding the
  device-side channel). On a fleet with many device nodes and few web nodes
  that is a large amount of cross-node traffic delivered to nodes that discard
  it. `Group.dispatch/3` only delivers to nodes that have a process joined for
  the key, so keystrokes, shell output and file transfers stay off uninvolved
  device nodes.

  Data-plane messages are delivered as `%Phoenix.Socket.Broadcast{}` structs,
  identical in shape to what `Phoenix.PubSub` delivered, so existing
  `handle_info(%Broadcast{...})` / `hooked_info(%Broadcast{...})` clauses in the
  channels, LiveView and tab components keep working unchanged — only the
  subscribe/broadcast call sites move here.

  ## Groups

  Console (per device id):

    * `console/<id>` — the device-side `ConsoleChannel` only. Its membership is
      the console liveness registry (`console_active?/1`) and the target for the
      user->device connect handshake (`connect_to_console/2`).
    * `device:console/<id>` — the `ConsoleChannel` *and* the device Show
      LiveView (whose `console_tab` consumes `file-data/*`). Carries the
      user->device stream (keystrokes, file transfer, API/script input).
    * `device:console:internal/<id>` — the device Show LiveView only. Carries
      the `console_joined` notification.
    * `user:console/<id>` — the user console channel and, as a fallback,
      `NervesHub.Scripts.Runner`. Carries the device->user output stream.

  Local shell (per device id):

    * `local_shell/<id>` — the device-side `ExtensionsChannel`, joined only
      while the `LocalShell` extension is attached. Its membership is the shell
      liveness registry (`local_shell_active?/1`) and the target for both the
      connect handshake and the user->device input stream.
    * `user:local_shell/<id>` — the user local-shell channel. Carries the
      device->user output stream.

  All groups use the default `:group` cluster: the device-side channels run on
  device nodes and the user channels / LiveViews run on web nodes, so both roles
  must be members of the same (default) cluster for dispatch to find them.
  """

  alias NervesHub.Extensions.LocalShell
  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  # -- Console: device-side channel -------------------------------------------

  @doc """
  Join the device-side console channel to the console liveness registry and the
  user->device stream group. Call once from `ConsoleChannel` after join.
  """
  @spec join_console(integer()) :: :ok
  def join_console(device_id) do
    :ok = Group.join(@group, console_key(device_id), %{})
    :ok = Group.join(@group, device_console_key(device_id), %{})
    :ok
  end

  @doc "Is a device-side console channel currently connected for this device?"
  @spec console_active?(integer()) :: boolean()
  def console_active?(device_id) do
    Group.members(@group, console_key(device_id)) != []
  end

  @doc """
  Monitor console liveness for this device. The calling process receives a
  `{:group, events, _}` message (carrying `%Group.Event{type: :joined | :left}`)
  whenever the device-side console channel joins or leaves.

  Membership presence is eventually consistent, so pair this with an initial
  `console_active?/1` read for the current value — and monitor *before* that read
  so a change in the gap still arrives as an event rather than being lost. The
  monitor is cleaned up automatically when the calling process dies, and
  `demonitor_console/1` releases it sooner.

  Calling this repeatedly for the same device is a no-op; see `monitor/1`.
  """
  @spec monitor_console(integer()) :: :ok
  def monitor_console(device_id) do
    monitor(console_key(device_id))
  end

  @doc "Stop monitoring console liveness for this device."
  @spec demonitor_console(integer()) :: :ok
  def demonitor_console(device_id) do
    :ok = Group.demonitor(@group, console_key(device_id))
  end

  @doc """
  Ask the device-side console channel to connect `pid` (the user channel). The
  channel replies directly to `pid` with its metadata and buffered output.
  """
  @spec connect_to_console(integer(), pid()) :: :ok
  def connect_to_console(device_id, pid) do
    Group.dispatch(@group, console_key(device_id), {:connect, pid})
  end

  @doc "Notify the device Show LiveView that the console channel has joined."
  @spec broadcast_console_joined(integer()) :: :ok
  def broadcast_console_joined(device_id) do
    message = %Broadcast{topic: internal_console_topic(device_id), event: "console_joined", payload: %{}}
    Group.dispatch(@group, internal_console_key(device_id), message)
  end

  # -- Console: user-side channel / Show LiveView -----------------------------

  @doc "Subscribe the device Show LiveView to the console groups it watches."
  @spec subscribe_console_watcher(integer()) :: :ok
  def subscribe_console_watcher(device_id) do
    :ok = Group.join(@group, device_console_key(device_id), %{})
    :ok = Group.join(@group, internal_console_key(device_id), %{})
    :ok
  end

  @doc "Subscribe the calling process to the device->user console output stream."
  @spec subscribe_user_console(integer()) :: :ok
  def subscribe_user_console(device_id) do
    :ok = Group.join(@group, user_console_key(device_id), %{})
  end

  @doc "Send a user->device console message (keystrokes, file transfer, input)."
  @spec broadcast_to_console(integer(), String.t(), map()) :: :ok
  def broadcast_to_console(device_id, event, payload) do
    message = %Broadcast{topic: device_console_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, device_console_key(device_id), message)
  end

  @doc "Send a device->user console message (output, file transfer)."
  @spec broadcast_to_user_console(integer(), String.t(), map()) :: :ok
  def broadcast_to_user_console(device_id, event, payload) do
    message = %Broadcast{topic: user_console_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, user_console_key(device_id), message)
  end

  # -- Local shell ------------------------------------------------------------

  @doc "Join the device-side extensions channel to the local-shell registry (on attach)."
  @spec join_local_shell(integer()) :: :ok
  def join_local_shell(device_id) do
    :ok = Group.join(@group, local_shell_key(device_id), %{})
  end

  @doc """
  Leave the local-shell registry (on detach).

  Leaving when never attached is not an error. `detach/1` is driven by a
  device-sent `local_shell:detached`, which `Extensions.Dispatch` delivers
  without checking that an `attached` came first -- and it does not rescue the
  call, so returning `Group.leave/2`'s `{:error, :not_in_group}` raw would let a
  device take down its own extensions channel by sending `detached` twice, or
  without ever attaching.
  """
  @spec leave_local_shell(integer()) :: :ok
  def leave_local_shell(device_id) do
    case Group.leave(@group, local_shell_key(device_id)) do
      :ok -> :ok
      {:error, :not_in_group} -> :ok
    end
  end

  @doc "Is the local shell currently attached on this device?"
  @spec local_shell_active?(integer()) :: boolean()
  def local_shell_active?(device_id) do
    Group.members(@group, local_shell_key(device_id)) != []
  end

  @doc """
  Monitor local-shell liveness for this device; see `monitor_console/1` for the
  seed-before-monitor ordering. The calling process receives `{:group, events,
  _}` when the shell attaches or detaches.
  """
  @spec monitor_local_shell(integer()) :: :ok
  def monitor_local_shell(device_id) do
    monitor(local_shell_key(device_id))
  end

  @doc "Stop monitoring local-shell liveness for this device."
  @spec demonitor_local_shell(integer()) :: :ok
  def demonitor_local_shell(device_id) do
    :ok = Group.demonitor(@group, local_shell_key(device_id))
  end

  @doc "Ask the device-side local shell to connect `pid` (the user channel)."
  @spec connect_to_local_shell(integer(), pid()) :: :ok
  def connect_to_local_shell(device_id, pid) do
    # The extensions channel routes `{module, msg}` to the matching attached
    # extension, so the tuple must carry the LocalShell module atom.
    Group.dispatch(@group, local_shell_key(device_id), {LocalShell, {:connect, pid}})
  end

  @doc "Send a user->device local-shell message (input, window size)."
  @spec broadcast_to_local_shell(integer(), String.t(), map()) :: :ok
  def broadcast_to_local_shell(device_id, event, payload) do
    message = %Broadcast{topic: local_shell_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, local_shell_key(device_id), message)
  end

  @doc "Subscribe the calling process to the device->user local-shell output stream."
  @spec subscribe_user_local_shell(integer()) :: :ok
  def subscribe_user_local_shell(device_id) do
    :ok = Group.join(@group, user_local_shell_key(device_id), %{})
  end

  @doc "Send a device->user local-shell message (output)."
  @spec broadcast_to_user_local_shell(integer(), String.t(), map()) :: :ok
  def broadcast_to_user_local_shell(device_id, event, payload) do
    message = %Broadcast{topic: user_local_shell_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, user_local_shell_key(device_id), message)
  end

  # `Group.monitor/2` registers into a `keys: :duplicate` registry, so it never
  # reports "already monitored" — every call leaves another row behind. Delivery
  # is unaffected (the library dedupes subscribers by pid before sending), but
  # the rows accumulate for the life of the caller, and the LiveView tabs that
  # monitor re-run `tab_params/3` on every navigation within the tab.
  # Unregistering first keeps it to exactly one.
  defp monitor(key) do
    :ok = Group.demonitor(@group, key)
    :ok = Group.monitor(@group, key)
  end

  # -- Group keys ("/" is Group's hierarchy separator) ------------------------

  defp console_key(device_id), do: "console/#{device_id}"
  defp device_console_key(device_id), do: "device:console/#{device_id}"
  defp internal_console_key(device_id), do: "device:console:internal/#{device_id}"
  defp user_console_key(device_id), do: "user:console/#{device_id}"
  defp local_shell_key(device_id), do: "local_shell/#{device_id}"
  defp user_local_shell_key(device_id), do: "user:local_shell/#{device_id}"

  # -- Topic strings (preserved as the previous `Phoenix.PubSub` topics) ------

  defp device_console_topic(device_id), do: "device:console:#{device_id}"
  defp internal_console_topic(device_id), do: "device:console:#{device_id}:internal"
  defp user_console_topic(device_id), do: "user:console:#{device_id}"
  defp local_shell_topic(device_id), do: "device:#{device_id}:extensions"
  defp user_local_shell_topic(device_id), do: "user:local_shell:#{device_id}"
end
