defmodule NervesHub.CLISessionCache do
  @moduledoc """
  CLI logins in progress, held in ETS on every web node.

  Every web node keeps a copy of every login, so any node can find one by its
  confirmation code (`with_confirmation_code/1`) or read it (`get/1`). Writes
  reach the other nodes over the `"cli_session_cache"` group in the `"web"`
  cluster, a moment later.

  Changes to a login go through one node, its owner, so that two nodes can't
  both act on the same copy of it. That is what stops a login confirmed on two
  nodes at once from minting two API tokens, and a ready login's token from
  being collected twice. See `get_and_update/2`.
  """

  use GenServer

  alias NervesHub.Accounts.UserCLISession
  alias NervesHub.DeviceLink.Handlers

  @table :cli_session_cache
  @group "cli_session_cache"
  @cluster "web"

  # The caches that can own logins. Kept apart from @group, which every cache
  # joins to receive writes, for two reasons. A node joins this one only once its
  # warm-up is done, so it never owns a login before it holds a copy of it. And a
  # node on a release from before owners existed never joins it, so it is never
  # sent a call it has no clause for.
  @owners "cli_session_cache/owners"

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
      if Application.get_env(:nerves_hub, :env) == :test do
        join_owners()
      else
        # Warm the cache from a peer once "web" membership has propagated (see
        # the note on @warm_up_attempts); best-effort, `put/2` fills it otherwise.
        # This node starts owning logins once that is done.
        Process.send_after(self(), {:warm_up_from_cluster, @warm_up_attempts}, @warm_up_interval)
        Process.send_after(self(), :delete_expired_session, 60_000)
      end

    {:ok, %{}}
  end

  defp join_owners() do
    :ok = Group.join(NervesHub.Group, @owners, %{}, cluster: @cluster)
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
    apply_from_peer({key, value, value.expires_at})
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
          Enum.each(data, &apply_from_peer/1)
          join_owners()

        :no_nodes_available when attempts > 1 ->
          Process.send_after(self(), {:warm_up_from_cluster, attempts - 1}, @warm_up_interval)

        :no_nodes_available ->
          # The first web node up, or none of the others answered. Either way
          # there is nothing more to wait for.
          join_owners()
      end

    {:noreply, state}
  end

  # A login only moves forward, from waiting to ready to collected, and a peer's
  # write can arrive late. Writes from two different nodes reach a third in no
  # set order, so the confirming node's `:ready` can land after another node's
  # `:collected`, and a peer's snapshot can be older than what this node has.
  # Applying either would put the collected API token back on this node until
  # the login expires, so a write that would move a login backwards is dropped.
  defp apply_from_peer({key, value, _expires_at} = entry) do
    case :ets.lookup(@table, key) do
      [{^key, current, _}] ->
        if stage(value) >= stage(current), do: :ets.insert(@table, entry)

      [] ->
        :ets.insert(@table, entry)
    end
  end

  # `:verified` is what a node on an older release stores for a collected login.
  defp stage(%{status: :waiting}), do: 0
  defp stage(%{status: :ready}), do: 1
  defp stage(%{status: status}) when status in [:collected, :verified], do: 2
  defp stage(_unknown), do: 0

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
  Reads the login under `key` and maybe writes it back, on the login's owner.

  `operation` is `{module, function, args}`. It is called as
  `apply(module, function, [current | args])`, where `current` is
  `{:ok, cli_session}` or `:error`, and must return `{return_value, action}`,
  where `action` is `{:put, cli_session}` or `:noop`. `get_and_update/2`
  returns `return_value`, and raises whatever the operation raised.

  It runs in the owner's cache process, one call at a time, so two callers
  can't both read a login before either writes it, whichever nodes they are on.
  The owner writes to its own table and replicates the write as `put/2` does.
  The operation is named rather than passed as a function, because a function
  sent to a node running a different build fails there with `:badfun`, as it
  would on every node during a rolling deploy.

  The owner is picked from the token among the caches in the owners group, by
  highest random weight (`owners/1`), so every node picks the same one and a
  change in membership only moves the logins of the node that joined or left.
  If the owner's cache has gone, or its node can't be reached, the next one in
  that order is asked, as every other node would. With no owner to ask, the
  operation runs on this node's cache.

  An owner that takes the call but doesn't answer within five seconds isn't
  replaced: it may already have run the operation, and running it again
  elsewhere is the race this prevents. The call exits, as a local call that
  timed out would.

  Every node picks the same owner only while they agree on who is in the group.
  For the moment after a node joins or leaves, while that news reaches the
  others, two nodes can still pick different owners for the same login. Nodes
  on a release from before owners existed don't route at all.
  """
  @spec get_and_update(term(), {module(), atom(), list()}) :: term()
  def get_and_update(key, {module, function, args} = operation)
      when is_atom(module) and is_atom(function) and is_list(args) do
    case call_owners(owners(key), key, operation) do
      {:raise, exception, stacktrace} -> reraise(exception, stacktrace)
      return -> return
    end
  end

  @doc false
  # Asks each owner in turn until one runs `operation`. Public for its tests,
  # which need an owner that has gone.
  @spec call_owners([pid()], term(), {module(), atom(), list()}) :: term()
  # No owners in sight: this node is still warming up and is the only web node
  # it knows of, or it can't reach the others.
  def call_owners([], key, operation) do
    GenServer.call(__MODULE__, {:run, key, operation})
  end

  def call_owners([owner | rest], key, operation) do
    GenServer.call(owner, {:run, key, operation})
  catch
    # The call never reached a running cache, so trying the next owner can't
    # repeat it. A node that went down while running the call is the exception:
    # nothing tells the two apart. It only matters if the operation had done
    # something outside the cache, such as minting a token, and hadn't written
    # the login back yet.
    :exit, {:noproc, {GenServer, :call, _}} -> call_owners(rest, key, operation)
    :exit, {{:nodedown, _node}, {GenServer, :call, _}} -> call_owners(rest, key, operation)
  end

  @doc """
  The caches that can own `key`, the owner first.

  Each cache in the owners group is weighed by a hash of `key` and its node's
  name, and the heaviest owns the login. Every node computes the same order
  from the same membership, and a cache joining or leaving only moves the
  logins it wins or held, not everyone's, as hashing modulo the number of
  nodes would.
  """
  @spec owners(term()) :: [pid()]
  def owners(key) do
    NervesHub.Group
    |> Group.members(@owners, cluster: @cluster)
    |> Enum.map(fn {pid, _meta} -> pid end)
    |> Enum.sort_by(&{:erlang.phash2({key, node(&1)}), node(&1)}, :desc)
  end

  def handle_call({:run, key, {module, function, args}}, _from, state) do
    current = get(key)

    try do
      case apply(module, function, [current | args]) do
        {return, {:put, cli_session}} ->
          _ = put(key, cli_session)
          {:reply, return, state}

        {return, :noop} ->
          {:reply, return, state}
      end
    rescue
      exception ->
        # Never let an operation crash the cache process; that would destroy
        # the ETS table (it has no heir) and drop every session.
        {:reply, {:raise, exception, __STACKTRACE__}, state}
    end
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, cli_session, _expires_at}] -> {:ok, cli_session}
      [] -> :error
    end
  end

  @doc """
  The unexpired sessions showing `code`, normally none or one.

  Sessions are keyed by their token, so this scans the table. It only ever
  holds the logins started in the last few minutes.
  """
  @spec with_confirmation_code(pos_integer()) :: [UserCLISession.t()]
  def with_confirmation_code(code) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    :ets.select(@table, [
      {{:_, %{confirmation_code: code}, :"$1"}, [{:>=, :"$1", now}], [:"$_"]}
    ])
    |> Enum.map(fn {_token, cli_session, _expires_at} -> cli_session end)
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
