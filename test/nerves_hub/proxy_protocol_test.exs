defmodule NervesHub.ProxyProtocolTest do
  use ExUnit.Case, async: true

  alias NervesHub.ProxyProtocol

  @signature <<13, 10, 13, 10, 0, 13, 10, 81, 85, 73, 84, 10>>

  @local 0x20
  @proxy 0x21

  @tcp_over_ipv4 0x11
  @tcp_over_ipv6 0x21

  describe "read_header/2" do
    test "reads the client behind an IPv4 connection" do
      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))

      assert {:ok, {{203, 0, 113, 7}, 51_234}} == read(header)
    end

    test "reads the client behind an IPv6 connection" do
      address = {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x1}
      header = header(@proxy, @tcp_over_ipv6, ipv6_block(address, 51_234))

      assert {:ok, {address, 51_234}} == read(header)
    end

    test "unwraps an IPv4 client announced inside the v4-mapped range" do
      mapped = {0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}
      header = header(@proxy, @tcp_over_ipv6, ipv6_block(mapped, 443))

      assert {:ok, {{203, 0, 113, 7}, 443}} == read(header)
    end

    test "ignores trailing type-length-value data after the addresses" do
      block = ipv4_block({203, 0, 113, 7}, 51_234) <> <<0x02, 0, 3, "alpn">>
      header = header(@proxy, @tcp_over_ipv4, block)

      assert {:ok, {{203, 0, 113, 7}, 51_234}} == read(header)
    end

    test "reports no client for the balancer's own connection" do
      header = header(@local, 0x00, <<>>)

      assert {:ok, nil} == read(header)
    end

    test "reports no client for a connection proxied over something other than TCP" do
      # 0x31 is UDP over IPv4.
      header = header(@proxy, 0x31, ipv4_block({203, 0, 113, 7}, 51_234))

      assert {:ok, nil} == read(header)
    end

    test "leaves the stream positioned at the client's first byte" do
      {client, server} = socket_pair()

      header = header(@proxy, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))
      :ok = :gen_tcp.send(client, header <> "client hello goes here")

      assert {:ok, {{203, 0, 113, 7}, 51_234}} = ProxyProtocol.read_header(server, 1_000)
      assert {:ok, "client hello goes here"} == :gen_tcp.recv(server, 0, 1_000)
    end

    test "consumes the address block of a header that reports no client" do
      {client, server} = socket_pair()

      # A LOCAL header may still carry an address block, and it still has to come
      # off the socket before whatever follows it.
      header = header(@local, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))
      :ok = :gen_tcp.send(client, header <> "client hello goes here")

      assert {:ok, nil} == ProxyProtocol.read_header(server, 1_000)
      assert {:ok, "client hello goes here"} == :gen_tcp.recv(server, 0, 1_000)
    end

    test "rejects a stream that opens with something else" do
      # The start of a TLS ClientHello: a handshake record for TLS 1.0+.
      assert {:error, :invalid_header} == read(<<0x16, 0x03, 0x01, 0x02, 0x00>> <> :binary.copy(<<0>>, 32))
    end

    test "rejects a version 1 header" do
      assert {:error, :invalid_header} == read("PROXY TCP4 203.0.113.7 10.0.0.1 51234 443\r\n")
    end

    test "rejects a version 2 header of a version we don't know" do
      header = header(0x31, @tcp_over_ipv4, ipv4_block({203, 0, 113, 7}, 51_234))

      assert {:error, :invalid_header} == read(header)
    end

    test "rejects a TCP header whose address block is truncated" do
      header = header(@proxy, @tcp_over_ipv4, <<203, 0, 113, 7>>)

      assert {:error, :invalid_header} == read(header)
    end

    test "reports a socket that closes mid-header" do
      {client, server} = socket_pair()

      :ok = :gen_tcp.send(client, @signature)
      :ok = :gen_tcp.close(client)

      assert {:error, :closed} == ProxyProtocol.read_header(server, 1_000)
    end

    test "reports a client that connects and says nothing" do
      {_client, server} = socket_pair()

      assert {:error, :timeout} == ProxyProtocol.read_header(server, 50)
    end
  end

  defp read(data) do
    {client, server} = socket_pair()

    :ok = :gen_tcp.send(client, data)

    ProxyProtocol.read_header(server, 1_000)
  end

  defp socket_pair() do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, port} = :inet.port(listener)
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener, 1_000)

    :ok = :gen_tcp.close(listener)

    on_exit(fn ->
      _ = :gen_tcp.close(client)
      _ = :gen_tcp.close(server)
    end)

    {client, server}
  end

  defp header(version_command, family_protocol, address_block) do
    <<@signature, version_command, family_protocol, byte_size(address_block)::16>> <> address_block
  end

  defp ipv4_block({a, b, c, d}, source_port) do
    <<a, b, c, d, 10, 0, 0, 1, source_port::16, 443::16>>
  end

  defp ipv6_block({a, b, c, d, e, f, g, h}, source_port) do
    destination = <<0x2001::16, 0xDB8::16, 0::80, 0x2::16>>

    <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> <>
      destination <> <<source_port::16, 443::16>>
  end
end
