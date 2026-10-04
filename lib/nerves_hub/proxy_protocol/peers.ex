defmodule NervesHub.ProxyProtocol.Peers do
  @moduledoc """
  The address each PROXY header gave, by socket, from the moment a connection is
  accepted until a while after its socket closes.

  `NervesHub.ProxyProtocol.TCP` reads the header in the TLS connection's process
  and is asked for the address from others, so it cannot live in a process
  dictionary. Nor can it go when the socket does: the handler serving a
  connection can still ask once the client has gone. Bandit does, for a client
  that hangs up straight after sending a request, and fails the connection if
  there is no answer. So this process monitors every socket it is told about,
  and forgets its address a minute after the socket closes, however it closed.
  """

  use GenServer

  @table __MODULE__

  # Long past the point anything serving the connection still asks.
  @remember_for 60_000

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, @remember_for, name: __MODULE__)

  @doc "Records a freshly accepted connection as still owing its header."
  @spec expect(:inet.socket()) :: :ok
  def expect(socket) do
    true = :ets.insert(@table, {socket, :pending})
    GenServer.cast(__MODULE__, {:watch, socket})
  end

  @doc "Whether the connection's header has yet to be read."
  @spec pending?(:inet.socket()) :: boolean()
  def pending?(socket), do: :ets.lookup(@table, socket) == [{socket, :pending}]

  @doc "Records the address to give for the connection. `nil` when there is none."
  @spec put(:inet.socket(), NervesHub.ProxyProtocol.peer() | nil) :: :ok
  def put(socket, peer) do
    true = :ets.insert(@table, {socket, peer || :no_address})
    :ok
  end

  @doc "The address recorded for the connection, or `nil` if there is none yet."
  @spec get(:inet.socket()) :: NervesHub.ProxyProtocol.peer() | nil
  def get(socket) do
    case :ets.lookup(@table, socket) do
      [{^socket, {_address, _port} = peer}] -> peer
      _no_address -> nil
    end
  end

  @impl GenServer
  def init(remember_for) do
    _ = :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

    {:ok, %{remember_for: remember_for}}
  end

  # A socket that has already closed is reported down straight away, so a
  # connection gone before this runs is still forgotten. Only the default inet
  # backend hands out ports, and only ports can be monitored.
  @impl GenServer
  def handle_cast({:watch, socket}, state) when is_port(socket) do
    _ref = :erlang.monitor(:port, socket)

    {:noreply, state}
  end

  def handle_cast({:watch, _not_a_port}, state), do: {:noreply, state}

  @impl GenServer
  def handle_info({:DOWN, _ref, :port, socket, _reason}, state) do
    _timer = Process.send_after(self(), {:forget, socket}, state.remember_for)

    {:noreply, state}
  end

  def handle_info({:forget, socket}, state) do
    true = :ets.delete(@table, socket)

    {:noreply, state}
  end
end
