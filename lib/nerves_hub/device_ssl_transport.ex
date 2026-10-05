defmodule NervesHub.DeviceSSLTransport do
  @moduledoc """
  SSL transport for device certificate authentication

  This transport exists to rate limit incoming SSL connections _before_ any
  ssl work has started. This let's us shed incoming devices before we waste
  a lot of resources on denying them midway through the SSL connection in
  the `NervesHub.SSL.verify_fun/3`

  It also, when configured to, recovers the device's own address from behind a
  load balancer. See `listen/2` and `handshake/1`. All other functions are
  delegated back to `ThousandIsland.Transports.SSL`.

  ## Running behind a TLS pass-through load balancer

  Devices authenticate with client certificates, so TLS has to terminate here
  rather than at the edge. A balancer in front of us therefore can't add an
  `X-Forwarded-For` header — it has no way into the stream — and the socket we
  accept is the balancer's own, opened over the platform's private network. The
  device's address is lost.

  The PROXY protocol closes that gap: the balancer writes a short header ahead
  of the client's first byte, which `NervesHub.ProxyProtocol.TCP` reads off
  underneath `:ssl` before TLS starts. Enable it with:

      config :nerves_hub, NervesHub.DeviceSSLTransport, proxy_protocol: :v2

  On Fly.io that pairs with a `proxy_proto` handler on the device service, and
  the setting belongs in the same file, in the same commit:

      [env]
        DEVICE_PROXY_PROTOCOL = "v2"

      [[services.ports]]
        port = 443
        handlers = ["proxy_proto"]
        proxy_proto_options = { version = "v2" }

  Both sides have to move together, and where they are configured decides
  whether they can. A balancer sending the header to a listener that isn't
  expecting it looks like a malformed ClientHello; a listener expecting a header
  that never arrives waits until it times out. Either way devices can't connect.

  Setting it through `fly secrets set` is the way to get exactly that: without
  `--stage` it restarts every machine as soon as it is run, so the whole fleet
  starts expecting a header that the handler won't send until the deploy that
  adds it. Keeping both in `fly.toml` means each machine picks up the pair
  together as the rolling deploy reaches it, and a rollback puts them back
  together too.
  """

  @behaviour ThousandIsland.Transport

  alias NervesHub.ProxyProtocol
  alias ThousandIsland.Transports.SSL

  # Bounds the TLS handshake, because `:ssl.handshake` waits forever unless given
  # a timeout. Without one, a client that connects and then stalls -- after a
  # well formed PROXY header, or straight away on a listener without one --
  # holds a connection process, its `:ssl` connection and a port for as long as
  # it likes. The rate limit in `handshake/1` caps how fast those arrive, not
  # how many can be open at once.
  #
  # Generous on purpose: a device on a poor cellular link doing full mutual TLS
  # is the case that must not be cut off, and 30s is far past any handshake that
  # was ever going to finish. `:tls_handshake_timeout` in this module's config
  # overrides it.
  @tls_handshake_timeout 30_000

  @impl ThousandIsland.Transport
  def listen(port, user_options) do
    if proxy_protocol() do
      # The header has to come off before TLS reads anything, so `:ssl` is given
      # a TCP transport that does that itself. The listener stays `:ssl`'s own
      # either way, which TLS 1.3 session tickets depend on: OTP only keeps a
      # ticket store for listeners it opened.
      SSL.listen(port, [{:cb_info, ProxyProtocol.TCP.cb_info()} | user_options])
    else
      SSL.listen(port, user_options)
    end
  end

  @impl ThousandIsland.Transport
  defdelegate accept(listener_socket), to: SSL

  @impl ThousandIsland.Transport
  def handshake(socket) do
    if NervesHub.RateLimit.increment() do
      :telemetry.execute([:nerves_hub, :rate_limit, :accepted], %{count: 1})

      # Behind the PROXY protocol the header is read as part of this, once
      # `:ssl` first reads from the socket.
      socket
      |> :ssl.handshake(tls_handshake_timeout())
      |> handshake_result()
    else
      :telemetry.execute([:nerves_hub, :rate_limit, :rejected], %{count: 1})

      {:error, :closed}
    end
  end

  # Both shapes are `:ssl`'s own: the third element carries protocol extensions
  # and is only present for the handshakes that negotiate any.
  defp handshake_result({:ok, ssl_socket}), do: {:ok, ssl_socket}
  defp handshake_result({:ok, ssl_socket, _protocol_extensions}), do: {:ok, ssl_socket}
  defp handshake_result({:error, reason}), do: {:error, reason}

  # Behind the PROXY protocol, `:ssl` asks `NervesHub.ProxyProtocol.TCP`, which
  # answers with the address from the header.
  @impl ThousandIsland.Transport
  defdelegate peername(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate upgrade(socket, opts), to: SSL

  @impl ThousandIsland.Transport
  defdelegate controlling_process(socket, pid), to: SSL

  @impl ThousandIsland.Transport
  defdelegate recv(socket, length, timeout), to: SSL

  @impl ThousandIsland.Transport
  defdelegate send(socket, data), to: SSL

  @impl ThousandIsland.Transport
  defdelegate sendfile(socket, filename, offset, length), to: SSL

  @impl ThousandIsland.Transport
  defdelegate getopts(socket, options), to: SSL

  @impl ThousandIsland.Transport
  defdelegate setopts(socket, options), to: SSL

  @impl ThousandIsland.Transport
  defdelegate shutdown(socket, way), to: SSL

  @impl ThousandIsland.Transport
  defdelegate close(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate sockname(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate peercert(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate secure?(), to: SSL

  @impl ThousandIsland.Transport
  defdelegate getstat(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate negotiated_protocol(socket), to: SSL

  @impl ThousandIsland.Transport
  defdelegate connection_information(socket), to: SSL

  defp proxy_protocol(), do: Keyword.get(config(), :proxy_protocol)

  defp tls_handshake_timeout() do
    Keyword.get(config(), :tls_handshake_timeout, @tls_handshake_timeout)
  end

  defp config(), do: Application.get_env(:nerves_hub, __MODULE__, [])
end
