defmodule NervesHubWeb.Helpers.ClientIP do
  @moduledoc """
  The address a device connected from, as far as the endpoint it reached can tell.

  The device endpoint terminates TLS itself, so anything in front of it can only
  pass the connection through and the device's address has to arrive out of
  band. `NervesHub.DeviceSSLTransport` puts it on the socket before any of this
  runs, so reading the socket's peer is enough there.

  The web endpoint is ordinary HTTPS, terminated ahead of us. Its socket peer is
  whatever terminated it, and the device's address arrives in a request header
  instead. Which header to use is a property of the platform deployment rather
  than of the request, so an endpoint names it in its config:

      config :nerves_hub, NervesHubWeb.Endpoint,
        forwarded_ip_header: "x-forwarded-for",
        forwarded_ip_trailing_hops: 0

  That is the default, because a web endpoint almost always has something in
  front of it, and reading the peer instead would quietly record the same
  balancer address for an entire fleet. An endpoint exposed directly should set
  it to `nil`: nothing is overwriting the header there, so it holds whatever the
  device chose to send.

  A forwarded header is a list, and the client owns the left of it: whatever it
  sent arrives untouched, with each proxy appending what it saw to the right. So
  the address is counted from the right, and `forwarded_ip_trailing_hops` says
  how many entries at that end belong to infrastructure rather than to the
  device. Nothing to the left of the entry we land on can shift it, which is
  what keeps a forged header harmless.

  Zero suits a proxy that appends only its own observation, which is what nginx
  does with `$proxy_add_x_forwarded_for`. Fly.io needs one: it appends two
  entries, the address it observed and then the app's own anycast address, so
  the device is second from the right and the rightmost entry is the same
  address for an entire fleet. Confirmed against a live request:

      x-forwarded-for: 1.2.3.4, 182.48.134.168, 66.241.125.59
                       ^ forged  ^ the device    ^ the app's Fly address

  Getting the count wrong records a plausible looking address belonging to the
  wrong machine, so confirm it against a real request rather than reasoning
  about it.

  The header has to start with `x-`. Phoenix hands a socket only the request
  headers with that prefix, so a balancer's own header, eg. Fly's `Fly-Client-IP`,
  never reaches us — which is why the count exists rather than reading the one
  header that would answer this by itself.
  """

  import Bitwise

  @doc """
  Where the device reached us from, formatted for storage, or `nil` if the
  connection couldn't tell us.

  `forwarded_header` is the header this endpoint trusts, or `nil` for an
  endpoint that trusts none. A trusted header that is absent, or that doesn't
  hold an address, falls back to the socket's peer -- the safe direction to
  fail, since the balancer's address is merely wrong, where a device's own
  claim about itself would be worse than wrong.
  """
  @spec resolve(map(), String.t() | nil, non_neg_integer()) :: String.t() | nil
  def resolve(connect_info, forwarded_header \\ nil, trailing_hops \\ 0)

  def resolve(connect_info, forwarded_header, trailing_hops) when is_binary(forwarded_header) do
    forwarded_address(connect_info, forwarded_header, trailing_hops) || peer_address(connect_info)
  end

  def resolve(connect_info, nil, _trailing_hops), do: peer_address(connect_info)

  defp peer_address(%{peer_data: %{address: address}}) when is_tuple(address), do: format(address)
  defp peer_address(_connect_info), do: nil

  # Counted from the right, past the entries the infrastructure appended. The
  # client owns the left of the list and can put anything it likes there, but it
  # cannot push its own value rightwards past the ones added after it, so the
  # entry we land on does not move.
  defp forwarded_address(%{x_headers: x_headers}, forwarded_header, trailing_hops) when is_list(x_headers) do
    x_headers
    |> Enum.filter(fn {header, _value} -> header == forwarded_header end)
    |> Enum.flat_map(fn {_header, value} -> String.split(value, ",") end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop(trailing_hops)
    |> List.first()
    |> parse()
  end

  defp forwarded_address(_connect_info, _forwarded_header, _trailing_hops), do: nil

  defp parse(nil), do: nil

  defp parse(address) do
    case :inet.parse_address(to_charlist(strip_port(address))) do
      {:ok, parsed} -> format(parsed)
      {:error, _reason} -> nil
    end
  end

  # Some proxies append the port they saw. An IPv6 address is bracketed when
  # they do, which is the only thing separating a port from the address's own
  # colons.
  defp strip_port("[" <> rest), do: rest |> String.split("]") |> List.first()

  defp strip_port(address) do
    case String.split(address, ":") do
      [ipv4, _port] -> ipv4
      _not_a_port -> address
    end
  end

  # An IPv4 client reaching an IPv6 listener is reported inside the v4-mapped
  # range. Unwrapping it means an address reads the same whichever endpoint and
  # whichever listener it arrived through — `NervesHub.ProxyProtocol` does the
  # same for the headers it reads.
  defp format({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    format({high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF})
  end

  defp format(address) do
    case :inet.ntoa(address) do
      {:error, _reason} -> nil
      formatted -> to_string(formatted)
    end
  end
end
