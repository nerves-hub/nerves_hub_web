defmodule NervesHub.DeviceSSLTransportTest do
  # Touches application env, and counts what NervesHub.ProxyProtocol.Peers
  # holds, so it can't share the node with anything else doing either.
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 2_000, interval: 20

  alias NervesHub.DeviceSSLTransport
  alias NervesHub.ProxyProtocol.Peers

  @signature <<13, 10, 13, 10, 0, 13, 10, 81, 85, 73, 84, 10>>

  @local 0x20
  @proxy 0x21
  @tcp_over_ipv4 0x11

  @fixtures Path.expand("../fixtures/ssl", __DIR__)

  # What the device endpoint adds with DEVICE_ENABLE_TLS_13=true.
  @tls_13 [versions: [:"tlsv1.3"], certificate_authorities: false, session_tickets: :stateless_with_cert]

  # Answers every connection with what the server believes about the other end,
  # which is the whole point of the transport.
  defmodule Reporter do
    use ThousandIsland.Handler

    @impl ThousandIsland.Handler
    def handle_connection(socket, state) do
      {:ok, {address, port}} = ThousandIsland.Socket.peername(socket)

      certificate =
        case ThousandIsland.Socket.peercert(socket) do
          {:ok, _der} -> "cert"
          {:error, _reason} -> "no-cert"
        end

      ThousandIsland.Socket.send(socket, "#{:inet.ntoa(address)}|#{port}|#{certificate}")

      {:close, state}
    end
  end

  # Asks who connected only once the client has gone, as Bandit does for a
  # client that hangs up straight after sending its request.
  defmodule AskAfterHangUp do
    use ThousandIsland.Handler

    @impl ThousandIsland.Handler
    def handle_connection(socket, test) do
      send(test, :connected)
      {:error, _closed} = ThousandIsland.Socket.recv(socket, 0, 5_000)
      gone(socket.socket)
      send(test, {:peer_after_hang_up, ThousandIsland.Socket.peername(socket)})

      {:close, test}
    end

    # `:ssl` reports the hang-up before its connection process has finished
    # closing the socket. Asking in between would pass whether or not the
    # address outlives the socket.
    defp gone(tls, attempts \\ 100) do
      case :ssl.connection_information(tls, [:protocol]) do
        {:error, _closed} -> :ok
        {:ok, _open} when attempts > 0 -> Process.sleep(10) && gone(tls, attempts - 1)
      end
    end
  end

  describe "with the PROXY protocol enabled" do
    setup do: start_server(proxy_protocol: :v2)

    test "reports the client the balancer announced, not the balancer", %{port: port} do
      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))

      assert {:ok, "203.0.113.7|51234|no-cert"} == connect(port, header)
    end

    test "still sees a device's certificate through the upgraded connection", %{port: port} do
      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))

      assert {:ok, "203.0.113.7|51234|cert"} == connect(port, header, client_certificate())
    end

    test "falls back to the socket for a health check from the balancer itself", %{port: port} do
      assert {:ok, reported} = connect(port, header(@local, 0x00, <<>>))
      assert ["127.0.0.1", _port, "no-cert"] = String.split(reported, "|")
    end

    test "hangs up on a connection that doesn't announce itself", %{port: port} do
      # What a client speaking straight TLS to a listener expecting a header
      # looks like. The bytes are consumed as a header, so the handshake that
      # follows can only fail.
      assert {:error, _reason} = connect(port, "")
    end

    test "forgets every address once its connection has closed", %{port: port} do
      forget_at_once()

      for source_port <- 50_000..50_004 do
        header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, source_port))

        assert {:ok, _reported} = connect(port, header)
      end

      # One is kept per connection, so anything left grows for as long as the
      # node is up.
      assert_eventually Enum.all?(
                          50_000..50_004,
                          &(:ets.match_object(Peers, {:_, {{203, 0, 113, 7}, &1}}) == [])
                        )
    end

    test "forgets a connection that ends without closing its socket" do
      # A crashed or killed connection closes its socket with its owner, and
      # nobody calls close/1 on the way out.
      forget_at_once()
      {socket, owner} = watched_socket()

      Process.exit(owner, :kill)

      assert_eventually not :ets.member(Peers, socket)
    end

    test "remembers an address for a while after its socket closes" do
      {socket, owner} = watched_socket()

      Process.exit(owner, :kill)
      assert_eventually is_nil(Port.info(socket))
      _ = :sys.get_state(Peers)

      assert Peers.get(socket) == {{203, 0, 113, 7}, 51_234}

      send(Peers, {:forget, socket})
    end

    test "still knows who connected once the client has gone" do
      {:ok, port: port, server: _server} =
        start_server([proxy_protocol: :v2], [], handler_module: AskAfterHangUp, handler_options: self())

      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))

      # Bandit asks then, for a client that leaves straight after its request,
      # and fails the connection with "Unable to obtain conn_data" if there is
      # no answer.
      assert {:ok, {{203, 0, 113, 7}, 51_234}} == peer_after_hang_up(port, header)

      # The balancer's own health check names no client, so the answer is the
      # socket's own address.
      assert {:ok, {{127, 0, 0, 1}, _port}} = peer_after_hang_up(port, header(@local, 0x00, <<>>))
    end
  end

  describe "TLS 1.3 session tickets" do
    test "are issued behind the PROXY protocol, and a device resumes with one" do
      {:ok, port: port, server: _server} = start_server([proxy_protocol: :v2], @tls_13)

      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))
      {reported, resumed?, tickets} = resume(port, header)

      assert reported == "203.0.113.7|51234|cert"
      refute resumed?

      assert tickets != [], """
      No TLS 1.3 session tickets were issued behind the PROXY protocol. OTP only
      keeps a ticket store for listeners `:ssl` opened, so a listener that
      accepts in the clear and upgrades by hand never issues one.
      """

      header = header(@proxy, @tcp_over_ipv4, ipv4_block({198, 51, 100, 9}, 40_000))
      {reported, resumed?, _tickets} = resume(port, header, use_ticket: [hd(tickets)])

      assert resumed?

      # DeviceSocket authenticates a device by its certificate, so a resumed
      # connection has to carry the one from the handshake it resumes.
      assert reported == "198.51.100.9|40000|cert"
    end

    test "are issued without the PROXY protocol, and a device resumes with one" do
      {:ok, port: port, server: _server} = start_server([proxy_protocol: nil], @tls_13)

      {_reported, false, [ticket | _]} = resume(port, "")
      {reported, resumed?, _tickets} = resume(port, "", use_ticket: [ticket])

      assert resumed?
      assert ["127.0.0.1", _port, "cert"] = String.split(reported, "|")
    end
  end

  describe "without the PROXY protocol" do
    setup do: start_server(proxy_protocol: nil)

    test "serves TLS directly and reports the socket's own peer", %{port: port} do
      assert {:ok, reported} = connect(port, "")
      assert ["127.0.0.1", _port, "no-cert"] = String.split(reported, "|")
    end

    test "still sees a device's certificate", %{port: port} do
      assert {:ok, reported} = connect(port, "", client_certificate())
      assert ["127.0.0.1", _port, "cert"] = String.split(reported, "|")
    end
  end

  # A client that opens a connection and never sends a ClientHello. Left alone,
  # it would hold a handler process, an `:ssl` connection and a port for as long
  # as it stayed quiet.
  describe "a client that stalls before the TLS handshake" do
    test "is hung up on without the PROXY protocol" do
      {:ok, port: port, server: server} = start_server(proxy_protocol: nil, tls_handshake_timeout: 100)

      socket = stall(port, "")

      assert hang_up(socket) == :closed
      assert_eventually {:ok, []} = ThousandIsland.connection_pids(server)
    end

    test "is hung up on after a PROXY header" do
      {:ok, port: port, server: server} = start_server(proxy_protocol: :v2, tls_handshake_timeout: 100)

      socket = stall(port, header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234)))

      assert hang_up(socket) == :closed
      assert_eventually {:ok, []} = ThousandIsland.connection_pids(server)
    end
  end

  defp start_server(config, transport_options \\ [], server \\ []) do
    previous = Application.get_env(:nerves_hub, DeviceSSLTransport, [])

    Application.put_env(:nerves_hub, DeviceSSLTransport, config)
    on_exit(fn -> Application.put_env(:nerves_hub, DeviceSSLTransport, previous) end)

    server =
      start_supervised!(
        {ThousandIsland,
         port: 0,
         handler_module: Keyword.get(server, :handler_module, Reporter),
         handler_options: Keyword.get(server, :handler_options, []),
         transport_module: DeviceSSLTransport,
         transport_options:
           Keyword.merge(
             [
               ip: {127, 0, 0, 1},
               keyfile: Path.join(@fixtures, "device.nerves-hub.org-key.pem"),
               certfile: Path.join(@fixtures, "device.nerves-hub.org.pem"),
               cacertfile: Path.join(@fixtures, "ca.pem"),
               verify: :verify_peer,
               verify_fun: {fn _certificate, _event, state -> {:valid, state} end, nil},
               fail_if_no_peer_cert: false,
               versions: [:"tlsv1.2"]
             ],
             transport_options
           )}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    {:ok, port: port, server: server}
  end

  # Opens a clear socket and writes `preamble`, then goes quiet.
  defp stall(port, preamble) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    if preamble != "", do: :ok = :gen_tcp.send(socket, preamble)

    socket
  end

  # `:closed` if the server hangs up within two seconds, `:timeout` if it is
  # still waiting. Anything it writes on the way out, an alert say, is read past.
  defp hang_up(socket) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, _bytes} -> hang_up(socket)
      {:error, reason} -> reason
    end
  end

  # Opens a clear socket, writes `preamble` (a PROXY header, or nothing), then
  # negotiates TLS over the top of it — which is the order the balancer sends in.
  defp connect(port, preamble, client_options \\ []) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    if preamble != "", do: :ok = :gen_tcp.send(socket, preamble)

    options =
      [
        verify: :verify_none,
        versions: [:"tlsv1.2"],
        server_name_indication: ~c"device.nerves-hub.org"
      ] ++ client_options

    with {:ok, ssl_socket} <- :ssl.connect(socket, options, 2_000),
         {:ok, reported} <- :ssl.recv(ssl_socket, 0, 2_000) do
      {:ok, to_string(reported)}
    end
  end

  # As `connect/3`, but as a device over TLS 1.3, keeping the session tickets the
  # server issues. Returns what the server reported, whether the session was
  # resumed, and the tickets.
  defp resume(port, preamble, client_options \\ []) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    if preamble != "", do: :ok = :gen_tcp.send(socket, preamble)

    options =
      [
        verify: :verify_none,
        versions: [:"tlsv1.3"],
        server_name_indication: ~c"device.nerves-hub.org",
        session_tickets: :manual
      ] ++ client_certificate() ++ client_options

    {:ok, ssl_socket} = :ssl.connect(socket, options, 2_000)
    {:ok, info} = :ssl.connection_information(ssl_socket, [:session_resumption])

    # Tickets are sent after the handshake, ahead of this.
    {:ok, reported} = :ssl.recv(ssl_socket, 0, 2_000)

    {to_string(reported), info[:session_resumption], receive_tickets([])}
  end

  # Completes a handshake behind `preamble`, hangs up, and returns what the
  # handler was then told about who connected.
  defp peer_after_hang_up(port, preamble) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, preamble)

    options = [verify: :verify_none, versions: [:"tlsv1.2"], server_name_indication: ~c"device.nerves-hub.org"]
    {:ok, ssl_socket} = :ssl.connect(socket, options, 2_000)

    assert_receive :connected
    :ok = :ssl.close(ssl_socket)

    assert_receive {:peer_after_hang_up, peer}, 5_000
    peer
  end

  # A socket NervesHub.ProxyProtocol.Peers watches and holds an address for,
  # owned by a process the test can kill.
  defp watched_socket() do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    test = self()

    owner =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
        :ok = Peers.expect(socket)
        :ok = Peers.put(socket, {{203, 0, 113, 7}, 51_234})
        send(test, {:socket, socket})
        Process.sleep(:infinity)
      end)

    assert_receive {:socket, socket}
    assert Peers.get(socket) == {{203, 0, 113, 7}, 51_234}

    {socket, owner}
  end

  # Peers keeps an address for a minute after its socket closes. Tests of the
  # forgetting itself have it forget straight away instead.
  defp forget_at_once() do
    %{remember_for: remember_for} = :sys.get_state(Peers)
    _ = :sys.replace_state(Peers, &%{&1 | remember_for: 0})
    on_exit(fn -> :sys.replace_state(Peers, &%{&1 | remember_for: remember_for}) end)
  end

  defp receive_tickets(tickets) do
    receive do
      {:ssl, :session_ticket, ticket} -> receive_tickets([ticket | tickets])
    after
      200 -> Enum.reverse(tickets)
    end
  end

  defp client_certificate() do
    [
      certfile: Path.join(@fixtures, "device-1234-cert.pem") |> to_charlist(),
      keyfile: Path.join(@fixtures, "device-1234-key.pem") |> to_charlist()
    ]
  end

  defp header(version_command, family_protocol, address_block) do
    <<@signature, version_command, family_protocol, byte_size(address_block)::16>> <> address_block
  end

  defp ipv4_block({a, b, c, d}, source_port) do
    <<a, b, c, d, 10, 0, 0, 1, source_port::16, 443::16>>
  end
end
