defmodule NervesHub.Extensions.PubSub do
  @moduledoc """
  Targeted pub/sub for the per-device extensions channel, backed by the
  `:group` library.

  This replaces the `Phoenix.PubSub` / `Phoenix.Channel.Server` broadcasts on
  the `"device:<id>:extensions"` topic. `Phoenix.PubSub` fans every extension
  message out to the pub/sub server on *every* node and filters locally; the
  only consumers are the device's own extensions channel (one device node) and,
  for reports, the LiveViews watching that device (a couple of web nodes), so a
  large fleet paid cross-node traffic for nothing. `Group.dispatch/3` delivers
  only to nodes with a joined member for the key.

  ## Two keys, split by direction

  The topic carried traffic in both directions, and the device-side extensions
  channel is a member *and* the origin of one of the flows. The old code relied
  on `broadcast_from!(self(), ...)` to keep the channel from receiving the
  report it just sent (which it would otherwise push straight back down to the
  device). `Group.dispatch` has no self-exclusion, so instead of reintroducing
  it we split the topic into two keys by direction — no process is ever both a
  sender and a member of the same key:

    * `device:extensions/<id>` — **web -> device.** The device-side
      `ExtensionsChannel` joins it; web callers (`request_health_check`,
      per-device extension enable/disable) dispatch `health:check` / `attach` /
      `detach` here, and the channel pushes them to the device.
    * `device:extensions:reports/<id>` — **device -> web.** The device Show
      LiveView joins it (its HealthTab/DetailsTab hooks consume
      `health_check_report`); the `ExtensionsChannel` dispatches the report
      here. The channel is *not* a member, so it never receives its own report.

  Messages are delivered as `%Phoenix.Socket.Broadcast{}` structs identical to
  what `Phoenix.PubSub` delivered, so existing
  `handle_info(%Broadcast{...})` / `hooked_info(%Broadcast{...})` clauses are
  unchanged.

  The product-wide `product:<id>:extensions` topic (dense fan-out to every
  device's extensions channel) intentionally stays on `Phoenix.PubSub`.

  Default `:group` cluster: the device-side channel runs on a device node and
  the report consumers on web nodes.
  """

  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc "Join the device-side extensions channel to receive web -> device events."
  @spec subscribe_device(integer()) :: :ok
  def subscribe_device(device_id) do
    Group.join(@group, device_key(device_id), %{})
  end

  @doc "Send a web -> device extensions event (`health:check`, `attach`, `detach`)."
  @spec broadcast_to_device(integer(), String.t(), map()) :: :ok
  def broadcast_to_device(device_id, event, payload) do
    message = %Broadcast{topic: topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, device_key(device_id), message)
  end

  @doc "Join the calling process (a device Show LiveView) to receive device -> web reports."
  @spec subscribe_reports(integer()) :: :ok
  def subscribe_reports(device_id) do
    Group.join(@group, reports_key(device_id), %{})
  end

  @doc "Send a device -> web extensions report (`health_check_report`)."
  @spec broadcast_report(integer(), String.t(), map()) :: :ok
  def broadcast_report(device_id, event, payload) do
    message = %Broadcast{topic: topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, reports_key(device_id), message)
  end

  # Group keys ("/" is Group's hierarchy separator).
  defp device_key(device_id), do: "device:extensions/#{device_id}"
  defp reports_key(device_id), do: "device:extensions:reports/#{device_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string.
  defp topic(device_id), do: "device:#{device_id}:extensions"
end
