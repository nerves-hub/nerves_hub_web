defmodule NervesHub.Consoles.PubSub do
  @moduledoc """
  Pub/sub for remote terminal access — the device console and the local shell
  extension.

  A device's terminal I/O is only ever consumed by the handful of processes in
  an open session: the user channel on a web node, and the device-side channel
  on whichever node holds the device. `Phoenix.PubSub` fans every message out to
  every node to be filtered locally, so the user-facing side, whose members
  exist only while somebody is looking, is on the `:group` library instead:
  `Group.dispatch/3` only delivers to nodes with a process joined for the key.

  The device side of the console is not, and that is deliberate. A `:group`
  member is replicated to every node in the cluster for as long as it exists,
  and the device-side console channel exists for the whole of every device's
  connection. A large fleet becomes hundreds of thousands of rows on every
  node, to serve messages that only flow while somebody has a console open.
  Instead the channel subscribes to a node-local `Phoenix.PubSub` topic, which
  costs nothing off its own node, and the user side finds it when it needs it:

    1. One broadcast to find the channel — `connect_to_console/2` for a session,
       `locate_console/1` for a page asking whether there is a console at all.
       It reaches every node, but only the node holding the device has a
       subscriber, and it happens once per user action.
    2. The channel replies directly with its pid.
    3. From then on, messages go straight to that pid (`send_to_console/4`),
       and a monitor on it is the liveness signal.

  Writers that do not hold a session (the device API's `code` endpoint,
  connecting code, `NervesHub.Scripts.Runner`) broadcast instead
  (`broadcast_to_console/3`), which costs a message per node per call.

  The local shell is found the same way, with one difference. It is an
  extension, and its handlers run wherever `NervesHub.DeviceLink` does, which is
  not always the node holding the connection, so it has no pid of the
  connection's to hand out. Its input is broadcast on the device's extensions
  topic instead, a message per node per keystroke, and the device page learns
  that it attached or detached from the extension rather than from a monitor.

  Data-plane messages are delivered as `%Phoenix.Socket.Broadcast{}` structs,
  identical in shape to what `Phoenix.PubSub` delivered, so existing
  `handle_info(%Broadcast{...})` / `hooked_info(%Broadcast{...})` clauses in the
  channels, LiveView and tab components match them whichever way they arrive.

  ## Topics and groups

  Console (per device id):

    * `device:console:<id>` — a `Phoenix.PubSub` topic, subscribed to by the
      device-side `ConsoleChannel` only. Carries the connect and locate
      requests, and the user->device stream from writers without a session.
      The channel answers `{:connect, pid}` with `{:metadata, console, metadata}`
      and `{:cache, scrollback}`, and `{:locate_console, pid, ref}` with
      `{:console_located, ref, console}`, each sent to `pid`.
    * `device:console:internal/<id>` (group) — the device Show LiveView only.
      Carries the `console_joined` notification and upload start/stop, and the
      local shell attaching and detaching.
    * `user:console/<id>` (group) — the user console channel and, as a fallback,
      `NervesHub.Scripts.Runner`. Carries the device->user output stream.

  Local shell (per device id):

    * `device:<id>:extensions` — the `Phoenix.PubSub` topic the device's
      `ExtensionsChannel` subscribes to for its whole connection (see
      `NervesHub.Extensions.PubSub`). Carries the connect and locate requests,
      tagged `{LocalShell, message}` so the channel hands them to the extension,
      which answers only while attached. Also carries the user->device input,
      which the channel pushes to the device.
    * `device:console:internal/<id>` (group) — as for the console; also carries
      the shell attaching and detaching.
    * `user:local_shell/<id>` (group) — the user local-shell channel. Carries the
      device->user output stream.

  All groups use the default `:group` cluster: their senders run on the nodes
  holding devices and their members on web nodes, or the other way round, so
  both roles have to be in the same (default) cluster for dispatch to find them.
  """

  alias NervesHub.Extensions.LocalShell
  alias Phoenix.Channel.Server, as: ChannelServer
  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group
  @pubsub NervesHub.PubSub

  # -- Console: device-side channel -------------------------------------------

  @doc """
  Subscribe the device-side console channel to the requests and input for its
  device. Call once from `ConsoleChannel` after join.

  A `Phoenix.PubSub` subscription, so it is node-local: holding it for the life
  of the device's connection costs nothing on any other node. See the moduledoc
  for why this side is not a `:group` member.
  """
  @spec subscribe_console(integer()) :: :ok
  def subscribe_console(device_id) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, device_console_topic(device_id))
  end

  @doc "Notify the device Show LiveView that the console channel has joined."
  @spec broadcast_console_joined(integer()) :: :ok
  def broadcast_console_joined(device_id) do
    message = %Broadcast{topic: internal_console_topic(device_id), event: "console_joined", payload: %{}}
    Group.dispatch(@group, internal_console_key(device_id), message)
  end

  # -- Console: finding the device-side channel -------------------------------

  @doc """
  Ask whether this device has a console channel, and where.

  If it has one, the channel replies to the caller with
  `{:console_located, ref, console}`, where `ref` is the reference returned
  here and `console` is the channel's pid. Nothing replies if there is no
  console, so the caller decides how long to wait; the channel answers in
  milliseconds when it exists. Monitoring `console` then tells the caller when
  it goes away.

  Broadcasts to every node, so call it on a user action (a page opening, a
  console coming up), not on a timer.
  """
  @spec locate_console(integer()) :: reference()
  def locate_console(device_id) do
    ref = make_ref()
    :ok = Phoenix.PubSub.broadcast!(@pubsub, device_console_topic(device_id), {:locate_console, self(), ref})
    ref
  end

  @doc """
  Ask the device-side console channel to connect `pid` (the user channel). The
  channel replies directly to `pid` with `{:metadata, console, metadata}`, then
  its buffered output as `{:cache, lines}`. `console` is where to send input
  from then on, with `send_to_console/4`.
  """
  @spec connect_to_console(integer(), pid()) :: :ok
  def connect_to_console(device_id, pid) do
    Phoenix.PubSub.broadcast!(@pubsub, device_console_topic(device_id), {:connect, pid})
  end

  # -- Console: user->device --------------------------------------------------

  @doc """
  Send a user->device console message (keystrokes, file transfer, input) from
  a session that knows the console's pid, or broadcast it when it does not
  (`nil`): before the channel's reply to `connect_to_console/2` has arrived, or
  after the channel it named has gone away.
  """
  @spec send_to_console(integer(), pid() | nil, String.t(), map()) :: :ok
  def send_to_console(device_id, nil, event, payload), do: broadcast_to_console(device_id, event, payload)

  def send_to_console(device_id, console, event, payload) do
    send(console, %Broadcast{topic: device_console_topic(device_id), event: event, payload: payload})
    :ok
  end

  @doc """
  Broadcast a user->device console message to whichever node holds the
  device's console channel.

  For writers that send a message or two without holding a session: it costs a
  message per node per call. A session sends with `send_to_console/4` instead.
  """
  @spec broadcast_to_console(integer(), String.t(), map()) :: :ok
  def broadcast_to_console(device_id, event, payload) do
    ChannelServer.broadcast!(@pubsub, device_console_topic(device_id), event, payload)
  end

  # -- Console: Show LiveView and user-side channel ---------------------------

  @doc "Subscribe the device Show LiveView to the console events it watches."
  @spec subscribe_console_watcher(integer()) :: :ok
  def subscribe_console_watcher(device_id) do
    :ok = Group.join(@group, internal_console_key(device_id), %{})
  end

  @doc """
  Tell the device Show LiveViews about console activity they display, such as
  an upload starting or finishing.
  """
  @spec broadcast_to_console_watchers(integer(), String.t(), map()) :: :ok
  def broadcast_to_console_watchers(device_id, event, payload) do
    message = %Broadcast{topic: internal_console_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, internal_console_key(device_id), message)
  end

  @doc "Subscribe the calling process to the device->user console output stream."
  @spec subscribe_user_console(integer()) :: :ok
  def subscribe_user_console(device_id) do
    :ok = Group.join(@group, user_console_key(device_id), %{})
  end

  @doc "Send a device->user console message (output, file transfer)."
  @spec broadcast_to_user_console(integer(), String.t(), map()) :: :ok
  def broadcast_to_user_console(device_id, event, payload) do
    message = %Broadcast{topic: user_console_topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, user_console_key(device_id), message)
  end

  # -- Local shell ------------------------------------------------------------

  @doc """
  Ask whether this device's local shell is attached.

  If it is, the `LocalShell` extension replies to the caller with
  `{:local_shell_located, ref}`, where `ref` is the reference returned here.
  Nothing replies otherwise, so the caller decides how long to wait. Like
  `locate_console/1`, it broadcasts to every node, so call it on a user action.
  """
  @spec locate_local_shell(integer()) :: reference()
  def locate_local_shell(device_id) do
    ref = make_ref()
    :ok = Phoenix.PubSub.broadcast!(@pubsub, local_shell_topic(device_id), {LocalShell, {:locate, self(), ref}})
    ref
  end

  @doc """
  Ask the device-side local shell to connect `pid` (the user channel). An
  attached shell replies to `pid` with its buffered output as `{:cache, lines}`.
  """
  @spec connect_to_local_shell(integer(), pid()) :: :ok
  def connect_to_local_shell(device_id, pid) do
    # The extensions channel routes `{module, msg}` to the matching attached
    # extension, so the tuple must carry the LocalShell module atom.
    Phoenix.PubSub.broadcast!(@pubsub, local_shell_topic(device_id), {LocalShell, {:connect, pid}})
  end

  @doc """
  Send a user->device local-shell message (input, window size).

  Broadcast, so it costs a message per node per call; see the moduledoc for why
  the local shell has no pid to send to instead.
  """
  @spec broadcast_to_local_shell(integer(), String.t(), map()) :: :ok
  def broadcast_to_local_shell(device_id, event, payload) do
    ChannelServer.broadcast!(@pubsub, local_shell_topic(device_id), event, payload)
  end

  @doc "Tell the device Show LiveViews that the local shell has attached."
  @spec broadcast_local_shell_attached(integer()) :: :ok
  def broadcast_local_shell_attached(device_id) do
    broadcast_to_console_watchers(device_id, "local_shell_attached", %{})
  end

  @doc "Tell the device Show LiveViews that the local shell has detached."
  @spec broadcast_local_shell_detached(integer()) :: :ok
  def broadcast_local_shell_detached(device_id) do
    broadcast_to_console_watchers(device_id, "local_shell_detached", %{})
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

  # -- Group keys ("/" is Group's hierarchy separator) ------------------------

  defp internal_console_key(device_id), do: "device:console:internal/#{device_id}"
  defp user_console_key(device_id), do: "user:console/#{device_id}"
  defp user_local_shell_key(device_id), do: "user:local_shell/#{device_id}"

  # -- Topic strings ----------------------------------------------------------
  #
  # `device:console:<id>` is a live `Phoenix.PubSub` topic. The rest are the
  # `Phoenix.PubSub` topics the groups replaced, kept as `%Broadcast{}` topics.

  defp device_console_topic(device_id), do: "device:console:#{device_id}"
  defp internal_console_topic(device_id), do: "device:console:#{device_id}:internal"
  defp user_console_topic(device_id), do: "user:console:#{device_id}"
  defp local_shell_topic(device_id), do: "device:#{device_id}:extensions"
  defp user_local_shell_topic(device_id), do: "user:local_shell:#{device_id}"
end
