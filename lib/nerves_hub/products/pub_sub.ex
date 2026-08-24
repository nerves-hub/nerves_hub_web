defmodule NervesHub.Products.PubSub do
  @moduledoc """
  Targeted pub/sub for product-scoped UI events, backed by the `:group` library.

  This replaces the `Phoenix.PubSub` broadcast on the `"product:<id>"` topic.
  The only consumers are LiveViews currently open for the product (firmware
  index, deployment group, device show), which all run on web nodes; a large
  fleet has many more device nodes, and `Phoenix.PubSub` fanned every event out
  to all of them to be discarded. `Group.dispatch` only delivers to nodes with
  a joined member.

  Events are delivered as `%Phoenix.Socket.Broadcast{}` structs whose `topic`
  is preserved as `"product:<id>"`, because receivers pattern-match on it
  (`%Broadcast{topic: "product:" <> _}`); only the subscribe/broadcast call
  sites move here.

  ## Self-exclusion

  `broadcast_from/3` mirrors `Phoenix.Channel.Server.broadcast_from/4`: it does
  not deliver to the calling process. This matters because the publisher is also
  a subscriber — `firmware/created` and `firmware/deleted` are published from
  inside the Firmware LiveView, which is subscribed to the product. That page
  already refreshes and flashes directly from the mutation's result, so it must
  not also receive the broadcast (which would double-flash). `Group.dispatch`
  has no self-exclusion, so we send to the group members minus `self()`.

  Default `:group` cluster.
  """

  alias Phoenix.Socket.Broadcast

  @group NervesHub.Group

  @doc "Join the calling process (a product-scoped LiveView) to the product's event group."
  @spec subscribe(integer()) :: :ok
  def subscribe(product_id) do
    :ok = Group.join(@group, key(product_id), %{})
  end

  @doc "Leave the product's event group."
  @spec unsubscribe(integer()) :: :ok
  def unsubscribe(product_id) do
    # Unsubscribing from something never subscribed to is not an error, matching
    # `Phoenix.PubSub.unsubscribe/2`, which callers here are drop-in replacing.
    case Group.leave(@group, key(product_id)) do
      :ok -> :ok
      {:error, :not_in_group} -> :ok
    end
  end

  @doc """
  Dispatch a product event to every joined process except the caller, mirroring
  `Phoenix.Channel.Server.broadcast_from/4`.
  """
  @spec broadcast_from(integer(), String.t(), map()) :: :ok
  def broadcast_from(product_id, event, payload) do
    message = %Broadcast{topic: topic(product_id), event: event, payload: payload}
    caller = self()

    for {pid, _meta} <- Group.members(@group, key(product_id)), pid != caller do
      send(pid, message)
    end

    :ok
  end

  # Group key. "/" is Group's hierarchy separator.
  defp key(product_id), do: "product/#{product_id}"

  # Preserved as the previous `Phoenix.PubSub` topic string; receivers match on
  # the `"product:" <> _` prefix.
  defp topic(product_id), do: "product:#{product_id}"
end
