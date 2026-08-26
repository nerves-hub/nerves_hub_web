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

  `health:check`, `attach` and `detach` are published by a UI button and by
  per-device extension toggles. They are *rare*, and the consumer -- the
  device's own `ExtensionsChannel` -- exists for as long as the device is
  connected. Putting that side on `:group` would mean a cluster-replicated join
  on every device connect and a leave on every disconnect, plus a row per online
  device on every node, to target a handful of operator-triggered messages. That
  is the same trade this module already declines for `product:<id>:extensions`
  below, and it is a worse one here because the churn scales with the fleet
  rather than with the number of open pages. A `Phoenix.PubSub` subscribe is
  node-local and costs nothing to hold.

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
  """

  alias NervesHub.Devices.Device
  alias NervesHub.Devices.DeviceMessages
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

  @doc "Send a web -> device extensions event (`health:check`, `attach`, `detach`)."
  @spec broadcast_to_device(Device.t(), String.t(), map()) :: :ok
  def broadcast_to_device(%Device{} = device, event, payload) do
    # Recorded here rather than in the channel that pushes it. The connection
    # holding the device is not always this node, and a connection reached over
    # `:erpc` has no database to write to, so this is the last point every
    # deployment has in common. See `NervesHub.Devices.DeviceMessages`.
    :ok = DeviceMessages.record(device, :sent, :extensions, event, payload)
    ChannelServer.broadcast!(NervesHub.PubSub, topic(device.id), event, payload)
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

  # Group key ("/" is Group's hierarchy separator).
  defp reports_key(device_id), do: "device:extensions:reports/#{device_id}"

  # Preserved as the previous `Phoenix.PubSub` topic strings.
  defp topic(device_id), do: "device:#{device_id}:extensions"
  defp product_topic(product_id), do: "product:#{product_id}:extensions"
end
