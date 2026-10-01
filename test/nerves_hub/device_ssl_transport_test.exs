defmodule NervesHub.DeviceSSLTransportTest do
  # Touches application env, so it can't share the node with anything reading it.
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 2_000, interval: 20

  alias NervesHub.DeviceSSLTransport

  @signature <<13, 10, 13, 10, 0, 13, 10, 81, 85, 73, 84, 10>>

  @local 0x20
  @proxy 0x21
  @tcp_over_ipv4 0x11

  @fixtures Path.expand("../fixtures/ssl", __DIR__)

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

  defp start_server(config) do
    previous = Application.get_env(:nerves_hub, DeviceSSLTransport, [])

    Application.put_env(:nerves_hub, DeviceSSLTransport, config)
    on_exit(fn -> Application.put_env(:nerves_hub, DeviceSSLTransport, previous) end)

    server =
      start_supervised!(
        {ThousandIsland,
         port: 0,
         handler_module: Reporter,
         transport_module: DeviceSSLTransport,
         transport_options: [
           ip: {127, 0, 0, 1},
           keyfile: Path.join(@fixtures, "device.nerves-hub.org-key.pem"),
           certfile: Path.join(@fixtures, "device.nerves-hub.org.pem"),
           cacertfile: Path.join(@fixtures, "ca.pem"),
           verify: :verify_peer,
           verify_fun: {fn _certificate, _event, state -> {:valid, state} end, nil},
           fail_if_no_peer_cert: false,
           versions: [:"tlsv1.2"]
         ]}
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
