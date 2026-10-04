defmodule NervesHub.ProxyProtocol.Peers do
  @moduledoc """
  The address each PROXY header gave, by socket, from the moment a connection is
  accepted until its socket closes.

  `NervesHub.ProxyProtocol.TCP` reads the header in the TLS connection's process
  and is asked for the address from others, so it cannot live in a process
  dictionary. A connection that ends abnormally closes its socket without
  anyone calling `forget/1`, so this process monitors every socket it is told
  about and forgets it when it goes, rather than relying on being told.
  """

  use GenServer

  @table __MODULE__

  @doc false
  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Records a freshly accepted connection as still owing its header."
  @spec expect(:inet.socket()) :: :ok
  def expect(socket) do
    true = :ets.insert(@table, {socket, :pending})
    GenServer.cast(__MODULE__, {:watch, socket})
  end

  @doc "Whether the connection's header has yet to be read."
  @spec pending?(:inet.socket()) :: boolean()
  def pending?(socket), do: :ets.lookup(@table, socket) == [{socket, :pending}]

  @doc """
  Records what the header said. `nil` is a header that named no client -- the
  balancer's own health check -- and is kept as read, with no address.
  """
  @spec put(:inet.socket(), NervesHub.ProxyProtocol.peer() | nil) :: :ok
  def put(socket, peer) do
    true = :ets.insert(@table, {socket, peer || :no_client})
    :ok
  end

  @doc "The client the header named, or `nil` if it named none or was never read."
  @spec get(:inet.socket()) :: NervesHub.ProxyProtocol.peer() | nil
  def get(socket) do
    case :ets.lookup(@table, socket) do
      [{^socket, {_address, _port} = peer}] -> peer
      _no_client -> nil
    end
  end

  @doc "Forgets a connection whose socket is being closed."
  @spec forget(:inet.socket()) :: :ok
  def forget(socket) do
    true = :ets.delete(@table, socket)
    :ok
  end

  @impl GenServer
  def init(nil) do
    _ = :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

    {:ok, nil}
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
    true = :ets.delete(@table, socket)

    {:noreply, state}
  end
end
