defmodule NervesHub.Devices.PubSub do
  @moduledoc """
  Targeted pub/sub for device -> UI events, backed by the `:group` library.

  This replaces the previous `Phoenix.PubSub` broadcast on the
  `"internal:device:<id>"` topic. `Phoenix.PubSub` fans every device event out to
  every node in the cluster and filters locally; most `internal:device:<id>`
  topics have zero or one UI watcher, so a large fleet pays cross-node traffic
  for nothing. `Group.dispatch/3` only delivers to nodes that have a process
  joined for the device's key, so a quiet device generates no cross-node traffic.

  Messages are delivered as `%Phoenix.Socket.Broadcast{}` structs, identical in
  shape to what `Phoenix.PubSub` previously delivered, so existing
  `handle_info(%Broadcast{...}, socket)` clauses in LiveViews and channels keep
  working unchanged — only the subscribe/broadcast call sites move here.
  """

  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc """
  Join the calling process to a device's event group.

  Membership is automatically cleaned up when the calling process dies, mirroring
  `Phoenix.PubSub` subscription behaviour.
  """
  @spec subscribe(integer()) :: :ok
  def subscribe(device_id) do
    :ok = Group.join(@group, key(device_id), %{})
  end

  @doc "Remove the calling process from a device's event group."
  @spec unsubscribe(integer()) :: :ok
  def unsubscribe(device_id) do
    # Unsubscribing from something never subscribed to is not an error, matching
    # `Phoenix.PubSub.unsubscribe/2`, which callers here are drop-in replacing.
    case Group.leave(@group, key(device_id)) do
      :ok -> :ok
      {:error, :not_in_group} -> :ok
    end
  end

  @doc """
  Dispatch an event to every process joined to the device's group.

  Returns `:ok` even when no process has joined the key — a device with no UI
  watcher is the common case and is not an error.
  """
  @spec broadcast(integer(), String.t(), term()) :: :ok
  def broadcast(device_id, event, payload) do
    message = %Broadcast{topic: topic(device_id), event: event, payload: payload}
    Group.dispatch(@group, key(device_id), message)
  end

  # Group key. "/" is Group's hierarchy separator, which keeps the door open for
  # future prefix queries (e.g. all devices in a product).
  defp key(device_id), do: "internal:device/#{device_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string so receivers that
  # parse the device id out of `Broadcast.topic` (e.g. the devices index
  # LiveView) keep working without change.
  defp topic(device_id), do: "internal:device:#{device_id}"
end
