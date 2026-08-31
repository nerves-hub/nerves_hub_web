defmodule NervesHub.ProxyProtocol do
  @moduledoc """
  Reads a PROXY protocol v2 header from a freshly accepted TCP socket.

  A load balancer that passes TLS through to us — Fly Proxy, for example — hides
  the device behind its own address: the socket we accept was opened by the
  balancer over the platform's private network, so `:inet.peername/1` reports
  the balancer. The PROXY protocol is how the balancer tells us who actually
  connected, by writing a short header ahead of the client's first byte.

  Only version 2 is supported. Version 1 is a variable length text line, so
  reading it means either consuming one byte at a time or overshooting into the
  TLS ClientHello — and an overshoot is unrecoverable, because those bytes can't
  be handed back to `:ssl.handshake/3`. Version 2 declares its own length, so
  every read is exact. Configure the balancer to send v2.
  """

  # The v2 header opens with a fixed 12 byte signature, chosen to be something
  # no real protocol would start with, then a byte of version and command, a
  # byte of address family and transport, and the length of everything after.
  @signature <<13, 10, 13, 10, 0, 13, 10, 81, 85, 73, 84, 10>>
  @fixed_header_size 16

  # High nibble 2 is the protocol version; the low nibble says whether the
  # connection is proxied on someone's behalf (1) or is the balancer's own (0).
  @local 0x20
  @proxy 0x21

  @tcp_over_ipv4 0x11
  @tcp_over_ipv6 0x21

  @type peer() :: {:inet.ip_address(), :inet.port_number()}
  @type error() :: :closed | :timeout | :invalid_header | :inet.posix()

  @doc """
  Read and consume the header, leaving the socket positioned at the client's
  first byte.

  Returns the client's address and port, or `nil` when the header describes no
  client worth reporting — a balancer health check, or a transport we can't
  represent as an address. Callers should fall back to the socket's own peer in
  that case rather than treating it as a failure.

  The socket must be in passive binary mode, which is how Thousand Island hands
  it to us.
  """
  @spec read_header(:inet.socket(), timeout()) :: {:ok, peer() | nil} | {:error, error()}
  def read_header(socket, timeout) do
    with {:ok, <<@signature, version_command, family_protocol, length::16>>} <-
           recv(socket, @fixed_header_size, timeout),
         {:ok, address_block} <- recv(socket, length, timeout) do
      parse(version_command, family_protocol, address_block)
    else
      {:ok, _no_signature} -> {:error, :invalid_header}
      {:error, reason} -> {:error, reason}
    end
  end

  # A zero length read means "everything available" to `:gen_tcp.recv/3`, which
  # would swallow the ClientHello. A header with no address block is legitimate
  # (LOCAL sends one), so answer it here rather than at the socket.
  defp recv(_socket, 0, _timeout), do: {:ok, <<>>}
  defp recv(socket, length, timeout), do: :gen_tcp.recv(socket, length, timeout)

  # The balancer's own connection, most often a health check. Its address block
  # is explicitly meaningless.
  defp parse(@local, _family_protocol, _address_block), do: {:ok, nil}

  defp parse(@proxy, @tcp_over_ipv4, <<source::binary-4, _destination::binary-4, port::16, _tlvs::binary>>) do
    {:ok, {ipv4(source), port}}
  end

  defp parse(@proxy, @tcp_over_ipv6, <<source::binary-16, _destination::binary-16, port::16, _tlvs::binary>>) do
    {:ok, {ipv6(source), port}}
  end

  # A TCP header whose address block didn't match above is truncated, which
  # means we've mis-framed the stream and whatever follows isn't a ClientHello.
  defp parse(@proxy, family_protocol, _address_block) when family_protocol in [@tcp_over_ipv4, @tcp_over_ipv6] do
    {:error, :invalid_header}
  end

  # Proxied over something other than TCP — UDP, a unix socket, unspecified.
  # Nothing here is an address we could store.
  defp parse(@proxy, _family_protocol, _address_block), do: {:ok, nil}

  defp parse(_version_command, _family_protocol, _address_block), do: {:error, :invalid_header}

  defp ipv4(<<a, b, c, d>>), do: {a, b, c, d}

  # An IPv4 client reaching an IPv6 listener is reported inside the v4-mapped
  # range. Unwrapping it keeps a device's address the same shape however the
  # balancer happened to describe it.
  defp ipv6(<<0::80, 0xFFFF::16, a, b, c, d>>), do: {a, b, c, d}

  defp ipv6(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>) do
    {a, b, c, d, e, f, g, h}
  end
end
