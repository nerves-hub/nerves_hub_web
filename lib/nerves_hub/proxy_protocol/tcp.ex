defmodule NervesHub.ProxyProtocol.TCP do
  @moduledoc """
  `:gen_tcp`, with the PROXY header taken off the front of each connection
  before TLS reads from it.

  Given to `:ssl.listen/2` as its `cb_info` transport, so that the listener is
  `:ssl`'s own. That is what TLS 1.3 session tickets need: OTP keeps a ticket
  store only for listeners it opened, so a socket accepted in the clear and
  upgraded with `:ssl.handshake/3` -- how the header used to be read -- is never
  issued one, and every device does a full handshake every time.

  `:ssl` calls this module as it would `:gen_tcp` and `:inet`, and everything is
  delegated to them except three things:

    * `accept/2` marks the connection as owing its header, and reads nothing. It
      runs in Thousand Island's acceptor, where one client that never sends a
      header would hold up every connection queued behind it.

    * The first read consumes the header: `:ssl` switching the socket to active,
      or a `recv/3`. That happens in the TLS connection's own process once
      `NervesHub.DeviceSSLTransport.handshake/1` has asked for a handshake, so
      the rate limit still runs before any of it.

    * `peername/1` answers with the address from the header. It is how
      `:ssl.peername/1`, and so Thousand Island, learns who connected. For a
      header naming no client -- the balancer's own health check -- it is the
      socket's address, taken while the header is read. Either way the answer
      no longer depends on the socket, which may have closed by the time
      Thousand Island asks.

  The addresses are kept in `NervesHub.ProxyProtocol.Peers`.
  """

  alias NervesHub.ProxyProtocol
  alias NervesHub.ProxyProtocol.Peers

  # Long enough to survive a slow link, short enough that a client which opens a
  # socket and says nothing can't hold a connection open. The header is a few
  # dozen bytes and the balancer writes it immediately.
  @header_timeout 5_000

  @doc "The `cb_info` for `:ssl.listen/2`: this module, with `:gen_tcp`'s message tags."
  @spec cb_info() :: {__MODULE__, :tcp, :tcp_closed, :tcp_error, :tcp_passive}
  def cb_info(), do: {__MODULE__, :tcp, :tcp_closed, :tcp_error, :tcp_passive}

  # Passive whatever else is asked for, so that nothing arrives as a message
  # before the header has been read off. `:ssl` asks for this anyway.
  def listen(port, options), do: :gen_tcp.listen(port, options ++ [active: false])

  def accept(listen_socket, timeout) do
    with {:ok, socket} <- :gen_tcp.accept(listen_socket, timeout) do
      :ok = Peers.expect(socket)

      {:ok, socket}
    end
  end

  # `:ssl` reads by switching the socket to active and taking messages, so the
  # first `{active, _}` it asks for is the moment the header has to come off.
  def setopts(socket, options) do
    if activates?(options) do
      with :ok <- take_header(socket), do: :inet.setopts(socket, options)
    else
      :inet.setopts(socket, options)
    end
  end

  def recv(socket, length), do: recv(socket, length, :infinity)

  def recv(socket, length, timeout) do
    with :ok <- take_header(socket), do: :gen_tcp.recv(socket, length, timeout)
  end

  def peername(socket) do
    case Peers.get(socket) do
      nil -> :inet.peername(socket)
      peer -> {:ok, peer}
    end
  end

  defdelegate close(socket), to: :gen_tcp
  defdelegate controlling_process(socket, pid), to: :gen_tcp
  defdelegate send(socket, data), to: :gen_tcp
  defdelegate shutdown(socket, how), to: :gen_tcp
  defdelegate getopts(socket, options), to: :inet
  defdelegate getstat(socket, options), to: :inet
  defdelegate port(socket), to: :inet
  defdelegate sockname(socket), to: :inet

  defp activates?(options) do
    Enum.any?(options, fn
      {:active, mode} -> mode != false
      _other -> false
    end)
  end

  # Only the first read on a connection does any work; the rest find the header
  # already taken.
  defp take_header(socket) do
    if Peers.pending?(socket) do
      case ProxyProtocol.read_header(socket, @header_timeout) do
        {:ok, nil} ->
          Peers.put(socket, own_address(socket))

        {:ok, peer} ->
          Peers.put(socket, peer)

        {:error, :timeout} ->
          {:error, :timeout}

        {:error, reason} ->
          # Nothing further on this socket can be trusted -- we've either
          # mis-framed the stream or we're talking to something that isn't the
          # balancer. `:ssl` treats a failed read as the socket closing, and
          # hangs up.
          :telemetry.execute([:nerves_hub, :proxy_protocol, :rejected], %{count: 1}, %{
            reason: reason
          })

          {:error, :closed}
      end
    else
      :ok
    end
  end

  defp own_address(socket) do
    case :inet.peername(socket) do
      {:ok, peer} -> peer
      {:error, _reason} -> nil
    end
  end
end
