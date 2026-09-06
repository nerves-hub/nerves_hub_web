defmodule NervesHub.Products.HealthProfiles.Cache do
  @moduledoc """
  Caches resolved health profiles, keyed by `{product_id, platform}`.

  A device's profile is read on every metric report — hundreds a second on a
  large fleet — and changes only when somebody edits one, so resolving it
  from the database each time re-reads the same handful of rows over and
  over. Entries are read straight out of ETS by the calling process, so a
  read costs no message and serialises against nothing.

  An edit drops the product's entries on the spot and tells the other nodes
  to do the same; the TTL is the backstop for a node that was not there to
  hear it, or that joined afterwards.

  This is configuration, not device state. An entry is derivable from the
  database at any moment, so an empty table costs a query and a briefly
  stale one costs a few seconds of a superseded threshold. Nothing here has
  to survive a restart, a redeployment, or a device moving between nodes —
  which is what keeps it a cache rather than the state this evaluation
  deliberately does without.
  """

  use GenServer

  @table __MODULE__
  @topic "health_profiles:changed"
  @default_ttl_ms to_timeout(second: 30)

  @typedoc "Product and the platform its firmware reports; `nil` platform is the product default."
  @type key() :: {pos_integer(), String.t() | nil}

  @doc """
  The cached value for `key`, or `fun.()` — stored under it and returned.

  `nil` is cached like anything else: a product with no profile is the case
  that would otherwise pay for a query on every report to learn nothing.
  """
  @spec fetch(key(), (-> value)) :: value when value: term()
  def fetch(key, fun) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _miss_or_expired ->
        value = fun.()
        true = :ets.insert(@table, {key, value, now + ttl_ms()})
        value
    end
  rescue
    # The table exists only once the cache has started. Without it every read
    # is a miss, which is a slower answer rather than a wrong one.
    ArgumentError -> fun.()
  end

  @doc """
  Forget everything cached for the product, here and on every other node.

  Called by `NervesHub.Products.HealthProfiles` after any change to a
  product's profiles or their metrics. The local drop is synchronous, so a
  read that follows an edit in the same process — the page reloading itself
  after a save — never sees the value it just replaced.
  """
  @spec invalidate(pos_integer()) :: :ok
  def invalidate(product_id) do
    :ok = drop(product_id)
    _ = Phoenix.PubSub.broadcast(NervesHub.PubSub, @topic, {:health_profiles_changed, product_id})
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
  def handle_info({:health_profiles_changed, product_id}, state) do
    :ok = drop(product_id)

    {:noreply, state}
  end

  # This process owns a table and a subscription and nothing else; an
  # unrecognised message is not a reason to drop either.
  def handle_info(_message, state), do: {:noreply, state}

  defp drop(product_id) do
    true = :ets.match_delete(@table, {{product_id, :_}, :_, :_})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ttl_ms(), do: Application.get_env(:nerves_hub, :health_profile_cache_ttl_ms, @default_ttl_ms)
end
