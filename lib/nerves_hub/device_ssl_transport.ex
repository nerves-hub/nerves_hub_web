defmodule NervesHub.DeviceSSLTransport do
  @moduledoc """
  SSL transport for device certificate authentication

  This transport exists to rate limit incoming SSL connections _before_ any
  ssl work has started. This let's us shed incoming devices before we waste
  a lot of resources on denying them midway through the SSL connection in
  the `NervesHub.SSL.verify_fun/3`

  It also, when configured to, recovers the device's own address from behind a
  load balancer. See `handshake/1` for both. All other functions are delegated
  back to `ThousandIsland.Transports.SSL` or, before the handshake has run,
  `ThousandIsland.Transports.TCP`.

  ## Running behind a TLS pass-through load balancer

  Devices authenticate with client certificates, so TLS has to terminate here
  rather than at the edge. A balancer in front of us therefore can't add an
  `X-Forwarded-For` header — it has no way into the stream — and the socket we
  accept is the balancer's own, opened over the platform's private network. The
  device's address is lost.

  The PROXY protocol closes that gap: the balancer writes a short header ahead
  of the client's first byte, which we read before starting TLS. Enable it with:

      config :nerves_hub, NervesHub.DeviceSSLTransport, proxy_protocol: :v2

  On Fly.io that pairs with a `proxy_proto` handler on the device service:

      [[services.ports]]
        port = 443
        handlers = ["proxy_proto"]
        proxy_proto_options = { version = "v2" }

  Both sides have to move together. A balancer sending the header to a listener
  that isn't expecting it looks like a malformed ClientHello, and a listener
  expecting a header that never arrives waits until it times out — either way
  devices can't connect, so treat turning this on as a single change to both.
  """

  @behaviour ThousandIsland.Transport

  alias NervesHub.ProxyProtocol
  alias ThousandIsland.Transports.SSL
  alias ThousandIsland.Transports.TCP

  require Logger

  # Matched structurally rather than against the record itself: `:ssl` has added
  # fields to `sslsocket` between OTP releases, and all we need to know is which
  # of the two transports a socket belongs to.
  defguardp is_tls_socket(socket) when is_tuple(socket) and elem(socket, 0) == :sslsocket

  # Where the client's address is kept between reading the PROXY header and
  # being asked for it. Thousand Island runs the handshake in the process that
  # owns the connection for its whole life, and that same process is the one
  # that later asks for `peername/1`, so there is nowhere for this to leak to.
  @peer_key {__MODULE__, :peer}

  # Options held back at listen time for the handshake to apply, keyed by the
  # port they were given for so that more than one listener can coexist.
  @ssl_options_key __MODULE__.SSLOptions

  # Long enough to survive a slow link, short enough that a client which opens a
  # socket and says nothing can't hold a connection process open. The header is
  # a few dozen bytes and the balancer writes it immediately.
  @proxy_header_timeout 5_000

  # Options that configure the listening socket rather than TLS. Everything else
  # in `transport_options` is held back for `:ssl.handshake/3`, which rejects
  # options it doesn't recognise.
  @tcp_listen_options [
    :backlog,
    :buffer,
    :delay_send,
    :dontroute,
    :exit_on_close,
    :high_msgq_watermark,
    :high_watermark,
    :ifaddr,
    :inet,
    :inet6,
    :inet_backend,
    :ip,
    :ipv6_v6only,
    :keepalive,
    :linger,
    :low_msgq_watermark,
    :low_watermark,
    :nodelay,
    :priority,
    :raw,
    :recbuf,
    :reuseaddr,
    :reuseport,
    :reuseport_lb,
    :send_timeout,
    :send_timeout_close,
    :sndbuf,
    :tos
  ]

  @impl ThousandIsland.Transport
  def listen(port, user_options) do
    if proxy_protocol() do
      # TLS can't start until the PROXY header has been read off the socket, and
      # it can't be read through `:ssl.transport_accept/1`. So we listen in the
      # clear and upgrade by hand once the header is out of the way.
      {tcp_options, ssl_options} = split_options(user_options)

      with {:ok, listener_socket} <- TCP.listen(port, tcp_options),
           {:ok, listening_port} <- :inet.port(listener_socket) do
        :persistent_term.put({@ssl_options_key, listening_port}, ssl_options)

        {:ok, listener_socket}
      end
    else
      SSL.listen(port, user_options)
    end
  end

  @impl ThousandIsland.Transport
  def accept(listener_socket), do: transport(listener_socket).accept(listener_socket)

  @impl ThousandIsland.Transport
  def handshake(socket) do
    if NervesHub.RateLimit.increment() do
      :telemetry.execute([:nerves_hub, :rate_limit, :accepted], %{count: 1})

      do_handshake(socket)
    else
      :telemetry.execute([:nerves_hub, :rate_limit, :rejected], %{count: 1})

      {:error, :closed}
    end
  end

  # Already a TLS socket, so the listener was opened by `:ssl` and there is no
  # PROXY header to read.
  defp do_handshake(socket) when is_tls_socket(socket), do: SSL.handshake(socket)

  defp do_handshake(socket) do
    with {:ok, peer} <- read_proxy_header(socket),
         {:ok, ssl_options} <- ssl_options(socket),
         {:ok, ssl_socket} <- SSL.upgrade(socket, ssl_options) do
      # A header can legitimately describe no client (a health check from the
      # balancer itself), in which case the socket's own peer is the truth.
      if peer, do: Process.put(@peer_key, peer)

      {:ok, ssl_socket}
    end
  end

  defp read_proxy_header(socket) do
    case ProxyProtocol.read_header(socket, @proxy_header_timeout) do
      {:ok, peer} ->
        {:ok, peer}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        # Nothing further on this socket can be trusted — we've either mis-framed
        # the stream or we're talking to something that isn't the balancer. Hang
        # up, and report it as a closed socket: those and TLS alerts are the only
        # failures Thousand Island understands here.
        :telemetry.execute([:nerves_hub, :proxy_protocol, :rejected], %{count: 1}, %{reason: reason})

        # Logged as well as counted while this is being confirmed on a
        # deployment: a listener expecting a header that the balancer isn't
        # sending rejects every device, and a silent rejection gives nothing to
        # diagnose it with.
        Logger.warning("[DeviceIPCheck] rejected a connection: #{inspect(reason)}")

        {:error, :closed}
    end
  end

  # The options `listen/2` held back, found by the port the connection arrived
  # on. `sockname/1` on an accepted socket is the listener's own address.
  defp ssl_options(socket) do
    case :inet.sockname(socket) do
      {:ok, {_address, port}} -> {:ok, :persistent_term.get({@ssl_options_key, port})}
      {:error, _reason} -> {:error, :closed}
    end
  end

  @impl ThousandIsland.Transport
  def peername(socket) do
    case Process.get(@peer_key) do
      nil -> transport(socket).peername(socket)
      peer -> {:ok, peer}
    end
  end

  @impl ThousandIsland.Transport
  def upgrade(socket, opts), do: transport(socket).upgrade(socket, opts)

  @impl ThousandIsland.Transport
  def controlling_process(socket, pid), do: transport(socket).controlling_process(socket, pid)

  @impl ThousandIsland.Transport
  def recv(socket, length, timeout), do: transport(socket).recv(socket, length, timeout)

  @impl ThousandIsland.Transport
  def send(socket, data), do: transport(socket).send(socket, data)

  @impl ThousandIsland.Transport
  def sendfile(socket, filename, offset, length) do
    transport(socket).sendfile(socket, filename, offset, length)
  end

  @impl ThousandIsland.Transport
  def getopts(socket, options), do: transport(socket).getopts(socket, options)

  @impl ThousandIsland.Transport
  def setopts(socket, options), do: transport(socket).setopts(socket, options)

  @impl ThousandIsland.Transport
  def shutdown(socket, way), do: transport(socket).shutdown(socket, way)

  @impl ThousandIsland.Transport
  def close(socket), do: transport(socket).close(socket)

  @impl ThousandIsland.Transport
  def sockname(socket), do: transport(socket).sockname(socket)

  @impl ThousandIsland.Transport
  def peercert(socket), do: transport(socket).peercert(socket)

  @impl ThousandIsland.Transport
  defdelegate secure?(), to: SSL

  @impl ThousandIsland.Transport
  def getstat(socket), do: transport(socket).getstat(socket)

  @impl ThousandIsland.Transport
  def negotiated_protocol(socket), do: transport(socket).negotiated_protocol(socket)

  @impl ThousandIsland.Transport
  def connection_information(socket), do: transport(socket).connection_information(socket)

  # Which transport a socket belongs to. Every connection is a TLS one by the
  # time it reaches a handler; the clear socket only exists between accepting
  # and handshaking, where Thousand Island may still ask for its peer, hand it
  # to another process, or close it.
  defp transport(socket) when is_tls_socket(socket), do: SSL
  defp transport(_socket), do: TCP

  defp split_options(options) do
    Enum.split_with(options, fn
      {key, _value} -> key in @tcp_listen_options
      key when is_atom(key) -> key in @tcp_listen_options
    end)
  end

  defp proxy_protocol() do
    :nerves_hub
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:proxy_protocol)
  end
end
