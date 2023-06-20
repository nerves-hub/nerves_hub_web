defmodule NervesHub.Tracker do
  @moduledoc """
  Track device online state

  When a device is marked as online, the state is broadcast to the cluster
  via an `abcast` to it's shard genserver. There are 8 shards to help lower
  the amount of mail in each shard's mailbox.

  A HLClock is started for each node that syncs between nodes in order to
  keep the clocks roughly in sync.
  """

  use Supervisor

  alias NervesHub.Tracker.DeviceShard

  @doc false
  def all_online() do
    0..7
    |> Enum.map(fn i ->
      :ets.select(:"tracker_shards_#{i}", [{:_, [], [{:element, 1, :"$_"}]}])
    end)
    |> Enum.concat()
  end

  @doc """
  Mark a device as online
  """
  def online(device) do
    {:ok, now} = HLClock.now(NervesHub.Clock)

    record = %{
      identifier: device.identifier,
      pid: self(),
      node: node(),
      timestamp: now
    }

    GenServer.abcast(DeviceShard.name(shard(device)), {:online, record})
  end

  @doc """
  Mark a device as offline
  """
  def offline(device) do
    {:ok, now} = HLClock.now(NervesHub.Clock)

    record = %{
      identifier: device.identifier,
      timestamp: now
    }

    GenServer.abcast(DeviceShard.name(shard(device)), {:offline, record})
  end

  @doc """
  String version of `offline/1`
  """
  def status(device) do
    if online?(device) do
      "online"
    else
      "offline"
    end
  end

  @doc """
  Check if a device is currently online

  Checks the local shard directly, if present, the device is online
  """
  def online?(device) do
    case :ets.lookup(DeviceShard.name(shard(device)), device.identifier) do
      [] ->
        false

      [_] ->
        true
    end
  end

  @doc false
  def shard(device) do
    device.identifier
    |> String.to_charlist()
    |> Enum.sum()
    |> rem(8)
  end

  @doc false
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(_opts) do
    children =
      Enum.map(0..7, fn i ->
        Supervisor.child_spec({DeviceShard, index: i}, id: :"shard_#{i}")
      end)

    children = [
      {HLClock, name: NervesHub.Clock},
      {NervesHub.ClockSync, [sync_interval: 3_000, clock: NervesHub.Clock]}
      | children
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule NervesHub.Tracker.DeviceShard do
  @moduledoc """
  A shard of the overall state of device tracking

  Starts an ets table and manages devices coming and going offline. If the device
  is local to the shard, it is monitored. When the device goes offline on the same node,
  and the device didn't declare itself as offline, the device is set as offline.

  Remote nodes are watched as well and clears out any devices that were online on that
  node when it goes offline.

  When the shard comes online, it picks a random node and asks it's counterpart on that
  node to sync over the full set of state.
  """

  use GenServer

  require Logger

  defmodule State do
    defstruct [:ets_table, :index]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name(opts[:index]))
  end

  def name(index) do
    :"tracker_shards_#{index}"
  end

  def init(opts) do
    state = %State{
      ets_table: name(opts[:index]),
      index: opts[:index]
    }

    :ets.new(state.ets_table, [:set, :protected, :named_table, read_concurrency: true])

    :net_kernel.monitor_nodes(true)

    Process.send_after(self(), :sync, 500)

    {:ok, state}
  end

  def handle_call(:start_sync, {pid, _from}, state) do
    {:reply, :ok, state, {:continue, {:sync, pid}}}
  end

  # NOTE this might become an issue as we start having very large amounts of devices online
  def handle_continue({:sync, pid}, state) do
    # select everything out at once, because otherwise we might miss something
    records = :ets.select(state.ets_table, [{:_, [], [{:element, 2, :"$_"}]}])

    Enum.each(records, fn record ->
      GenServer.cast(pid, {:online, record})
    end)

    {:noreply, state}
  end

  def handle_cast({:offline, record}, state) do
    Logger.debug("Offline device #{record.identifier} from shard #{state.index}")

    case :ets.lookup(state.ets_table, record.identifier) do
      [] ->
        {:noreply, state}

      [{_identifier, existing_record}] ->
        # only perform the delete if it's a new message and we didn't receive an
        # out of date message by accident
        if HLClock.before?(existing_record.timestamp, record.timestamp) do
          :ets.delete(state.ets_table, record.identifier)
        end

        {:noreply, state}
    end
  end

  def handle_cast({:online, record}, state) do
    Logger.debug("Online device #{record.identifier} from shard #{state.index}")

    # monitor the process if its local to clear the device once it is terminated,
    # as a precaution for the device not calling it's own `terminate`.
    if :erlang.node(record.pid) == node() do
      Process.monitor(record.pid)
    end

    case :ets.lookup(state.ets_table, record.identifier) do
      [] ->
        :ets.insert(state.ets_table, {record.identifier, record})
        {:noreply, state}

      [{_identifier, existing_record}] ->
        if HLClock.before?(existing_record.timestamp, record.timestamp) do
          :ets.insert(state.ets_table, {record.identifier, record})
        end

        {:noreply, state}
    end
  end

  def handle_info(:sync, state) do
    case Node.list() do
      [] ->
        {:noreply, state}

      nodes ->
        node = Enum.random(nodes)
        :ok = GenServer.call({name(state.index), node}, :start_sync)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case :ets.select(state.ets_table, [{{:_, %{pid: pid}}, [], [:"$_"]}]) do
      [] ->
        {:noreply, state}

      [{_id, record}] ->
        {:ok, now} = HLClock.now(NervesHub.Clock)
        record = %{record | timestamp: now}
        GenServer.abcast(name(state.index), {:offline, record})
        {:noreply, state}
    end
  end

  def handle_info({:nodedown, node}, state) do
    deleted_count = :ets.select_delete(state.ets_table, [{{:_, %{node: node}}, [], [true]}])
    Logger.debug("Deleted #{deleted_count} devices from node in shard #{state.index}")
    {:noreply, state}
  end

  def handle_info({:nodeup, _node}, state) do
    {:noreply, state}
  end
end

defmodule NervesHub.ClockSync do
  @moduledoc false

  # Taken from Groot

  # This module regularly sends our local HLC to a random node in our cluster.
  # Each node in the cluster does this periodically in order to passively
  # keep HLCs in close proximity to each other. This synchronization is naive
  # but it works fine for small cluster sizes. On large clusters it would be
  # better to use views similar to HyParView ensure messages converge efficiently.

  use GenServer

  alias __MODULE__

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def sync_remote_clock(server, hlc) do
    GenServer.cast(server, {:sync_remote_clock, hlc})
  end

  def init(args) do
    data = %{
      sync_interval: Keyword.fetch!(args, :sync_interval),
      clock: Keyword.fetch!(args, :clock)
    }

    schedule_sync(data)

    {:ok, data}
  end

  def handle_cast({:sync_remote_clock, hlc}, data) do
    HLClock.recv_timestamp(data.clock, hlc)
    {:noreply, data}
  end

  def handle_info(:sync, data) do
    case Node.list() do
      [] ->
        schedule_sync(data)
        {:noreply, data}

      nodes ->
        node = Enum.random(nodes)
        {:ok, hlc} = HLClock.send_timestamp(data.clock)
        ClockSync.sync_remote_clock({ClockSync, node}, hlc)
        schedule_sync(data)
        {:noreply, data}
    end
  end

  def handle_info(_msg, data) do
    {:noreply, data}
  end

  defp schedule_sync(%{sync_interval: interval}) do
    Process.send_after(self(), :sync, interval)
  end
end
