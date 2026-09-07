defmodule NervesHub.Extensions.PubSub do
  @moduledoc """
  Pub/sub for the per-device extensions channel.

  The `"device:<id>:extensions"` topic carried traffic in both directions, and
  the two directions want opposite transports.

  ## device -> web: `:group`

  `device:extensions:reports/<id>` carries `health_check_report`. The only
  consumers are LiveViews currently watching that device -- almost always none
  -- so `Phoenix.PubSub` fanned every report out to the pub/sub server on every
  node for nobody to read. Membership is sparse and short-lived (it exists only
  while somebody has the page open), which is exactly what `Group.dispatch/3`
  is good at: a report from a device nobody is watching generates no cross-node
  traffic at all.

  ## web -> device: `Phoenix.PubSub`

  `attach` and `detach` are published by per-device extension toggles. They are
  *rare*, and the consumer -- the device's own `ExtensionsChannel` -- exists for
  as long as the device is connected. Putting that side on `:group` would mean a
  cluster-replicated join on every device connect and a leave on every
  disconnect, plus a row per online device on every node, to target a handful of
  operator-triggered messages. That is the same trade this module already
  declines for `product:<id>:extensions` below, and it is a worse one here
  because the churn scales with the fleet rather than with the number of open
  pages. A `Phoenix.PubSub` subscribe is node-local and costs nothing to hold.

  `device:<extension>/<id>` is the one exception, and it earns it: a paced
  extension needs a message from an open page (see `watch/2`), and there is no
  `Phoenix.PubSub` topic that reaches one device's connection without every node
  in the cluster hearing about it. The join is per *attached extension* rather
  than per connection, and it buys targeted delivery for something that would
  otherwise be fleet-wide fan-out.

  Reports are delivered as `%Phoenix.Socket.Broadcast{}` structs identical to
  what `Phoenix.PubSub` delivered, so existing `handle_info(%Broadcast{...})` /
  `hooked_info(%Broadcast{...})` clauses are unchanged.

  ## Self-exclusion

  The device-side channel is a consumer of the web -> device flow *and* the
  origin of the report flow. The old code relied on `broadcast_from!(self(),
  ...)` to keep it from receiving the report it just sent (which it would push
  straight back down to the device). Splitting the directions removes the need:
  the channel is not a member of the reports group, so it can never receive its
  own report.

  ## Product-wide config

  `product:<id>:extensions` (`subscribe_product/1`, `broadcast_to_product/3`)
  stays on `Phoenix.PubSub` for the reason above, doubled: one publish must
  reach *every* online device in the product, so it is genuine dense fan-out
  with no targeted-dispatch win. It lives here only so that all extension
  pub/sub goes through one module.

  ## Transport only, deliberately

  Nothing here touches the database, and that has to stay true. The
  device-facing half of this module -- `subscribe_device/1`,
  `subscribe_product/1`, and the topic strings both ends compute -- runs in the
  process holding the device's connection, and since the `NervesHub.DeviceLink`
  contract that process is not always on a node carrying the platform stack.
  `NervesHub.DeviceLink.Dispatcher.Remote` exists so a connection can be held
  somewhere that reaches DeviceLink over `:erpc`, with no `Repo`, no schemas and
  no `NervesHub.Devices.DeviceMessages`.

  A schema in a function head or a context call in a body is not a soft
  constraint there: the struct fails to expand and the call warns as undefined,
  so the module cannot be built at all. Recording therefore belongs with
  whatever produced the message, which is on a web node in every case -- see
  `NervesHub.Extensions.broadcast_extension_event/3`.

  `NervesHub.Consoles.PubSub` is the same shape for the same reason.
  """

  alias NervesHub.Extensions
  alias Phoenix.Channel.Server, as: ChannelServer
  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc """
  Subscribe the device-side extensions channel to web -> device events.

  Node-local, so holding it for the life of the device's connection costs
  nothing off-node -- see the moduledoc on why this direction is not on
  `:group`.
  """
  @spec subscribe_device(integer()) :: :ok
  def subscribe_device(device_id) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic(device_id))
  end

  @doc """
  Send a web -> device extensions event (`health:check`, `attach`, `detach`).

  Recording the message is the caller's, because it is the caller that produces
  it -- see the moduledoc's note on what this module does not do.
  """
  @spec broadcast_to_device(integer(), String.t(), map()) :: :ok
  def broadcast_to_device(device_id, event, payload) do
    ChannelServer.broadcast!(NervesHub.PubSub, topic(device_id), event, payload)
  end

  @doc "Join the calling process (a device Show LiveView) to receive device -> web reports."
  @spec subscribe_reports(integer()) :: :ok
  def subscribe_reports(device_id) do
    :ok = Group.join(@group, reports_key(device_id), %{})
  end

  @doc "Send a device -> web extensions report (`health_check_report`)."
  @spec broadcast_report(integer(), String.t(), map()) :: :ok
  def broadcast_report(device_id, event, payload) do
    message = %Broadcast{topic: topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, reports_key(device_id), message)
  end

  # -- Health: who is watching a device right now -----------------------------

  @doc """
  The group key a device's extensions channel joins while a paced extension is
  attached, so an open page can tell it to report more often.

  `Health` and `Metrics` both use it, each with its own key, so a page open on a
  device speeds up whichever of them that device is running.

  Public because the join cannot happen here: `Group.join/4` joins the calling
  process, and the process that has to be a member is the one holding the
  device's connection. An extension therefore returns a `{:group_join, key}`
  effect and lets the connection carry it out -- the same reason
  `NervesHub.Consoles.PubSub.local_shell_key/1` is public.
  """
  @spec watch_key(integer(), Extensions.extension()) :: String.t()
  def watch_key(device_id, extension), do: "device:#{extension}/#{device_id}"

  @doc """
  Watch a device's `extension` from the calling process (a device Show LiveView).

  Two things happen, and they answer different questions.

  The join is the standing answer to "is anybody still watching?", which is what
  a paced extension reads when it decides to *slow back down*. Membership is the
  right shape for that: a page closing, a browser tab going away and a LiveView
  crashing all look the same, and none of them can send a message on the way
  out. It is also why there is no matching unwatch -- the membership lasts
  exactly as long as the process that took it, which is exactly as long as
  somebody is looking.

  The dispatch is what makes the *speed up* immediate. The extension could read
  the membership instead, but that read runs wherever the extension runs, which
  is not necessarily the node this join was made on, and group state is
  eventually consistent -- a read in that gap would miss the page that just
  opened and nothing further would arrive to correct it. Announcing needs no
  read at all.
  """
  @spec watch(integer(), Extensions.extension()) :: :ok
  def watch(device_id, extension) do
    :ok = Group.join(@group, watchers_key(device_id, extension), %{})

    # The extensions channel routes `{module, msg}` to the matching attached
    # extension, so the tuple has to carry the module.
    Group.dispatch(@group, watch_key(device_id, extension), {Extensions.module(extension), :watching})
  end

  @doc "Is anybody watching this device's `extension` right now?"
  @spec watched?(integer(), Extensions.extension()) :: boolean()
  def watched?(device_id, extension) do
    Group.members(@group, watchers_key(device_id, extension)) != []
  end

  # -- Product-wide extension config (stays on Phoenix.PubSub) -----------------

  @doc """
  Subscribe the calling process (a device's extensions channel) to product-wide
  extension `attach`/`detach` events.
  """
  @spec subscribe_product(integer()) :: :ok
  def subscribe_product(product_id) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, product_topic(product_id))
  end

  @doc """
  Broadcast a product-wide extension event (`attach`/`detach`) to every device's
  extensions channel subscribed for the product. Excludes the caller, matching
  the previous `broadcast_from!` behaviour.
  """
  @spec broadcast_to_product(integer(), String.t(), map()) :: :ok
  def broadcast_to_product(product_id, event, payload) do
    ChannelServer.broadcast_from!(NervesHub.PubSub, self(), product_topic(product_id), event, payload)
  end

  # Group keys ("/" is Group's hierarchy separator).
  defp reports_key(device_id), do: "device:extensions:reports/#{device_id}"
  defp watchers_key(device_id, extension), do: "device:#{extension}:watchers/#{device_id}"

  # Preserved as the previous `Phoenix.PubSub` topic strings.
  defp topic(device_id), do: "device:#{device_id}:extensions"
  defp product_topic(product_id), do: "product:#{product_id}:extensions"
end
