defmodule NervesHub.CLISessionCache do
  use GenServer

  @table :cli_session_cache
  @group "cli_session_cache"
  @cluster "web"

  # Peer "web" cluster membership propagates asynchronously after this node
  # joins, so the cache warm-up retries pulling from a peer for a short window.
  @warm_up_attempts 5
  @warm_up_interval 250

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    _ = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    :ok = Group.join(NervesHub.Group, @group, %{}, cluster: @cluster)

    _ =
      if Application.get_env(:nerves_hub, :env) != :test do
        # Warm the cache from a peer once "web" membership has propagated (see
        # the note on @warm_up_attempts); best-effort, `put/2` fills it otherwise.
        Process.send_after(self(), {:warm_up_from_cluster, @warm_up_attempts}, @warm_up_interval)
        Process.send_after(self(), :delete_expired_session, 60_000)
      end

    {:ok, %{}}
  end

  def handle_info({:put, origin, _key, _value}, state) when origin == node() do
    # Our own write echoed back over the group. The ETS table was already
    # updated synchronously in `put/2`, so there is nothing to do.
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

  def handle_info({:warm_up_from_cluster, attempts}, state) do
    _ =
      case fetch_data_from_cluster() do
        {:ok, data} ->
          :ets.insert(@table, data)

        :no_peers_available when attempts > 1 ->
          Process.send_after(self(), {:warm_up_from_cluster, attempts - 1}, @warm_up_interval)

        :no_peers_available ->
          :ok
      end

    {:noreply, state}
  end

  def put(key, cli_session) do
    :ets.insert(@table, {key, cli_session, cli_session.expires_at})

    _ =
      Group.dispatch(
        NervesHub.Group,
        @group,
        {:put, node(), key, cli_session},
        cluster: @cluster
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
  on their node-local ETS copies until the group dispatch propagates between them,
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
    # Only web nodes run this cache and join the "web" group, so pull from a peer
    # that has actually joined — not any connected node (`Node.list/0` would
    # include device nodes, whose RPC has no `@table` and always fails).
    peer_nodes =
      NervesHub.Group
      |> Group.members(@group, cluster: @cluster)
      |> Enum.map(fn {pid, _meta} -> node(pid) end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == node()))

    fetch_from_peers(peer_nodes)
  end

  defp fetch_from_peers([]), do: :no_peers_available

  defp fetch_from_peers([target_node | rest]) do
    # :ets.tab2list/1 converts the entire ETS table into a list of tuples
    case :rpc.call(target_node, :ets, :tab2list, [@table]) do
      data when is_list(data) -> {:ok, data}
      {:badrpc, _reason} -> fetch_from_peers(rest)
    end
  end
end
