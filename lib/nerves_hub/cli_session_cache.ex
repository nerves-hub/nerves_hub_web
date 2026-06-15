defmodule NervesHub.CLISessionCache do
  use GenServer

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

  def handle_info({:put, key, value}, state) do
    _ = put(key, value)
    {:noreply, state}
  end

  def handle_info(:delete_expired_session, state) do
    delete_expired_sessions()
    Process.send_after(self(), :delete_expired_session, 60_000)
    {:noreply, state}
  end

  def put(key, cli_session) do
    :ets.insert(@table, {key, cli_session, cli_session.expires_at})
    _ = Phoenix.PubSub.broadcast_from(NervesHub.PubSub, self(), "cli_session_cache", {:put, key, cli_session})
    :ok
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
    # Gets all connected nodes excluding the current node
    nodes = Node.list()

    if Enum.empty?(nodes) do
      :no_nodes_available
    else
      # Query the first available node to dump its table via RPC
      [target_node | _] = nodes

      # :ets.tab2list/1 converts the entire ETS table into a list of tuples
      case :rpc.call(target_node, :ets, :tab2list, [@table]) do
        {:badrpc, _reason} -> :no_nodes_available
        data when is_list(data) -> {:ok, data}
      end
    end
  end
end
