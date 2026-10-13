defmodule NervesHub.Webhooks.Cache do
  @moduledoc """
  Caches which of a product's webhooks are enabled and what each subscribes to,
  keyed by product id.

  Every device event asks this: each connect, disconnect, health report and
  metrics batch, on whichever node holds the device's connection. Nearly every
  product has no webhooks at all, so asking the database each time would add a
  query to the hottest paths in the platform to learn nothing. Entries are read
  straight out of ETS by the calling process, so a read costs no message and
  serialises against nothing.

  A change to a product's webhooks drops its entry on the spot and tells the
  other nodes to do the same; the TTL is the backstop for a node that was not
  there to hear it.

  Only ids and event types are cached. URLs and secrets are read by the
  delivery worker when it sends, so a stale entry can at worst send one
  delivery for an event the webhook has just stopped subscribing to, and the
  worker drops deliveries for webhooks that have been disabled or deleted.

  Modelled on `NervesHub.Products.HealthProfiles.Cache`.
  """

  use GenServer

  @table __MODULE__
  @topic "webhooks:changed"
  @default_ttl_ms to_timeout(second: 30)

  @doc """
  The cached value for `product_id`, or `fun.()` — stored under it and returned.

  `nil` is cached like anything else: it is what a product with no webhooks
  stores, and that is the case that would otherwise cost a query per event.
  """
  @spec fetch(pos_integer(), (-> value)) :: value when value: term()
  def fetch(product_id, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, product_id) do
      [{^product_id, value, expires_at}] when expires_at > now ->
        value

      _miss_or_expired ->
        value = fun.()
        true = :ets.insert(@table, {product_id, value, now + ttl_ms()})
        value
    end
  rescue
    # The table exists only once the cache has started. Without it every read
    # is a miss, which is a slower answer rather than a wrong one.
    ArgumentError -> fun.()
  end

  @doc """
  Forget what is cached for the product, here and on every other node.

  The local drop is synchronous, so an event raised by the process that just
  changed a webhook already sees the change.
  """
  @spec invalidate(pos_integer()) :: :ok
  def invalidate(product_id) do
    :ok = drop(product_id)
    _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, @topic, {:webhooks_changed, product_id})
    :ok
  end

  @doc "Empty the cache. For tests, where the database is rolled back beneath it."
  @spec reset() :: :ok
  def reset() do
    true = :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    _ =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, @topic)

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:webhooks_changed, product_id}, state) do
    :ok = drop(product_id)

    {:noreply, state}
  end

  # This process owns a table and a subscription and nothing else; an
  # unrecognised message is not a reason to drop either.
  def handle_info(_message, state), do: {:noreply, state}

  defp drop(product_id) do
    true = :ets.delete(@table, product_id)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ttl_ms(), do: Application.get_env(:nerves_hub, :webhooks_cache_ttl_ms, @default_ttl_ms)
end
