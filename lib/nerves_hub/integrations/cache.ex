defmodule NervesHub.Integrations.Cache do
  @moduledoc """
  Caches who hears a product's events (`NervesHub.Integrations`) and which
  events each wants, keyed by product id.

  Every device event asks this: each connect, disconnect, health report and
  metrics batch, on whichever node holds the device's connection. Nearly every
  product has no webhooks at all, so asking the database each time would add a
  query to the hottest paths in the platform to learn nothing. Entries are read
  straight out of ETS by the calling process, so a read costs no message and
  serialises against nothing.

  Integrations belong to the organization, so each entry also records the
  product's organization, and a change to any of an organization's
  integrations drops the entries of all its products, on the spot here and by
  message on the other nodes. The TTL is the backstop for a node that was not
  there to hear it.

  Only ids and event types are cached. Where an event goes (a URL, a
  channel) and how it is signed are read when it is sent, so a stale entry can
  at worst send one event that has just stopped being wanted, and deliveries
  for anything since disabled or deleted are dropped.

  Modelled on `NervesHub.Products.HealthProfiles.Cache`.
  """

  use GenServer

  @table __MODULE__
  @topic "integrations:changed"
  @default_ttl_ms to_timeout(second: 30)

  @doc """
  The cached value for `product_id`, or the value from `fun.()`, stored under
  it and returned.

  `fun` returns `{org_id, value}`: the product's organization, so the entry
  can be dropped when the organization's webhooks change, and the value.
  `org_id` is `nil` for a product that no longer exists.

  `nil` is cached like any other value: it is what a product nobody hears
  stores, and that is the case that would otherwise cost a query per event.
  """
  @spec fetch(pos_integer(), (-> {pos_integer() | nil, value})) :: value when value: term()
  def fetch(product_id, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, product_id) do
      [{^product_id, _org_id, value, expires_at}] when expires_at > now ->
        value

      _miss_or_expired ->
        {org_id, value} = fun.()
        true = :ets.insert(@table, {product_id, org_id, value, now + ttl_ms()})
        value
    end
  rescue
    # The table exists only once the cache has started. Without it every read
    # is a miss, which is a slower answer rather than a wrong one.
    ArgumentError -> fun.() |> elem(1)
  end

  @doc """
  Forget what is cached for every product of the organization, here and on
  every other node.

  The local drop is synchronous, so an event raised by the process that just
  changed a webhook already sees the change.
  """
  @spec invalidate(pos_integer()) :: :ok
  def invalidate(org_id) do
    :ok = drop(org_id)
    _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, @topic, {:integrations_changed, org_id})
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
  def handle_info({:integrations_changed, org_id}, state) do
    :ok = drop(org_id)

    {:noreply, state}
  end

  # This process owns a table and a subscription and nothing else; an
  # unrecognised message is not a reason to drop either.
  def handle_info(_message, state), do: {:noreply, state}

  # A scan of the table, which holds one entry per product with devices on
  # this node: cheap enough for something that happens when a person edits a
  # webhook.
  defp drop(org_id) do
    true = :ets.match_delete(@table, {:_, org_id, :_, :_})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ttl_ms(), do: Application.get_env(:nerves_hub, :integrations_cache_ttl_ms, @default_ttl_ms)
end
