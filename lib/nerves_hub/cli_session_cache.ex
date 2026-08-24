defmodule NervesHub.CLISessionCache do
  use GenServer

  alias NervesHub.DeviceLink.Handlers

  @table :cli_session_cache

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    _ = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    case fetch_data_from_cluster() do
      {:ok, data} ->
        :ets.insert(@table, data)

      :no_nodes_available ->
        :ok
    end

    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, "cli_session_cache")

    _ =
      if Application.get_env(:nerves_hub, :env) != :test do
        Process.send_after(self(), :delete_expired_session, 60_000)
      end

    {:ok, %{}}
  end

  def handle_info({:put, origin, _key, _value}, state) when origin == node() do
    # Our own write echoed back over PubSub. The ETS table was already updated
    # synchronously in `put/2`, so there is nothing to do.
    {:noreply, state}
  end

  def handle_info({:put, _origin, key, value}, state) do
    # A write from a peer node. Apply it locally, but do NOT re-broadcast:
    # otherwise every node re-emits every message it receives and they
    # ping-pong across the cluster forever.
    :ets.insert(@table, {key, value, value.expires_at})
    {:noreply, state}
  end

  def handle_info(:delete_expired_session, state) do
    delete_expired_sessions()
    Process.send_after(self(), :delete_expired_session, 60_000)
    {:noreply, state}
  end

  def put(key, cli_session) do
    :ets.insert(@table, {key, cli_session, cli_session.expires_at})

    _ =
      Phoenix.PubSub.broadcast(
        NervesHub.PubSub,
        "cli_session_cache",
        {:put, node(), key, cli_session}
      )

    :ok
  end

  @doc """
  Atomically read a session and conditionally write it back.

  Runs `fun` inside the cache process so concurrent callers on this node cannot
  interleave a read and a write (e.g. a double-clicked confirmation or a retried
  request). `fun` receives the current value as `{:ok, cli_session}` or `:error`
  and must return `{return_value, action}` where `action` is `{:put, cli_session}`
  or `:noop`.

  Note: this serializes within a node only. Two different nodes can still race
  on their node-local ETS copies until the PubSub write propagates between them,
  matching the cache's best-effort cross-node consistency. Closing that window
  fully would require single-owner routing per token or a DB-level uniqueness
  guard on the minted token.
  """
  def get_and_update(key, fun) do
    case GenServer.call(__MODULE__, {:get_and_update, key, fun}) do
      {:raise, exception, stacktrace} -> reraise(exception, stacktrace)
      return -> return
    end
  end

  def handle_call({:get_and_update, key, fun}, _from, state) do
    current = get(key)

    try do
      case fun.(current) do
        {return, {:put, cli_session}} ->
          _ = put(key, cli_session)
          {:reply, return, state}

        {return, :noop} ->
          {:reply, return, state}
      end
    rescue
      exception ->
        # Never let a caller-supplied function crash the cache process; that
        # would destroy the ETS table (it has no heir) and drop every session.
        {:reply, {:raise, exception, __STACKTRACE__}, state}
    end
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, cli_session, _expires_at}] -> {:ok, cli_session}
      [] -> :error
    end
  end

  def delete_expired_sessions() do
    now = DateTime.utc_now() |> DateTime.to_unix()

    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])

    :ok
  end

  def clear() do
    :ets.delete_all_objects(@table)
    :ok
  end

  def count() do
    :ets.info(@table, :size)
  end

  defp fetch_data_from_cluster() do
    fetch_from(candidates())
  end

  # Prefer nodes known to carry the platform stack. `Node.list/0` is every node
  # that joined the topology, which is not the same thing: `device` nodes do not
  # run this cache, and neither does anything else that joins without carrying
  # the platform stack. Asking one of those for the table is a wasted round trip
  # at best.
  #
  # At boot the `:pg` group may not have synced yet, and a cold cache is worse
  # than an imperfect guess, so fall back to any connected node — `fetch_from/1`
  # skips whatever cannot answer.
  defp candidates() do
    case Handlers.nodes() -- [node()] do
      [] -> Node.list()
      platform -> platform
    end
  end

  defp fetch_from([]), do: :no_nodes_available

  # Walks the candidates rather than taking the head and giving up: a single
  # node that cannot answer used to leave this node with an empty cache for the
  # life of the process.
  defp fetch_from([node | rest]) do
    # :ets.tab2list/1 converts the entire ETS table into a list of tuples
    case :rpc.call(node, :ets, :tab2list, [@table]) do
      {:badrpc, _reason} -> fetch_from(rest)
      data when is_list(data) -> {:ok, data}
    end
  end
end
