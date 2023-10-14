defmodule NervesHub.LoadBalancer do
  @moduledoc """
  Determines whether the node is overloaded by scanning the online devices
  and if the node is running high, flips a switch to stop accepting new
  devices on this node. This is useful in a rolling deploy where the older
  a node is, the more likely it is to run significantly higher than new nodes
  coming in.

  Listens for nodes in the cluster to go offline which will result in a large
  device state sync. Accepting devices will be temporarily disabled across
  the cluster to help prevent state issues from popping up.

  *Note*: Currently this only logs when devices would be blocked to let it run
  in a production environment to see that devices would be blocked at
  appropriate times.
  """

  use GenServer

  require Logger

  @doc """
  Start the load balancer

  There are currently no options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(_opts) do
    Process.send_after(self(), :tick, 60_000)

    :net_kernel.monitor_nodes(true)

    {:ok, :undefined}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    nodes = [node() | Node.list()]

    device_counts =
      Enum.into(nodes, %{}, fn node ->
        counts =
          Enum.map(0..7, fn i ->
            :ets.select_count(:"tracker_shards_#{i}", [{{:_, %{node: node}}, [], [true]}])
          end)

        count = Enum.sum(counts)

        {node, count}
      end)

    average_count = Enum.sum(Map.values(device_counts)) / Enum.count(Map.values(device_counts))

    current_node_ratio = device_counts[node()] / average_count

    if current_node_ratio > 1.3 do
      Logger.info("[LoadBalancer] Current node ratio is high - #{current_node_ratio}")
    end

    Process.send_after(self(), :tick, 60_000)

    {:noreply, state}
  end

  def handle_info({:nodedown, _node}, state) do
    Logger.info("[LoadBalancer] Node went offline")
    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state) do
    Logger.info("[LoadBalancer] Node came online")
    {:noreply, state}
  end

  def handle_info(_other, state) do
    {:noreply, state}
  end
end
