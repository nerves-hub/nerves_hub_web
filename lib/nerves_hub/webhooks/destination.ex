defmodule NervesHub.Webhooks.Destination do
  @moduledoc """
  Where a webhook is allowed to send to.

  A webhook makes NervesHub send a request to an address somebody typed in,
  from inside NervesHub's own network. Left unchecked, that address could be
  the cloud provider's metadata service, a database, or anything else that
  trusts requests from its own subnet (server-side request forgery). So unless
  the instance allows private destinations, a webhook may only reach public
  addresses.

  The check happens twice. When a webhook is saved, a URL whose host is a
  literal private address is refused, so the mistake is reported where it is
  made. When a delivery is sent, the host is resolved and every address it
  resolves to is checked, and the request then goes to the address that was
  checked rather than resolving the name again. Resolving twice would let a DNS
  server answer the check with a public address and the connection with a
  private one.

  Self-hosted instances often deliver to receivers on their own network, which
  is what `WEBHOOKS_ALLOW_PRIVATE_DESTINATIONS` is for. With it set, nothing is
  resolved here and the HTTP client connects as it normally would.
  """

  import Bitwise

  # Networks a webhook may not reach unless private destinations are allowed:
  # loopback, private, link-local (which includes cloud metadata services),
  # carrier-grade NAT, and the reserved, documentation and multicast ranges no
  # webhook receiver legitimately lives in.
  @blocked_ipv4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  # `::/96` covers the unspecified and loopback addresses as well as the
  # deprecated IPv4-compatible form. IPv6 forms that carry an IPv4 address
  # (mapped, NAT64, 6to4) are checked by the address they carry instead; see
  # `embedded_ipv4/1`.
  @blocked_ipv6 [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 96},
    {{0x100, 0, 0, 0, 0, 0, 0, 0}, 64},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @resolve_timeout to_timeout(second: 5)

  @doc """
  Whether `url` is somewhere a webhook may be pointed, checking what can be
  checked without the network.

  Returns a message for the settings form when it is not.
  """
  @spec validate_url(String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_url(url, opts \\ []) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme}} when scheme not in ["http", "https"] ->
        {:error, "must start with https:// or http://"}

      {:ok, %URI{host: host}} when host in [nil, ""] ->
        {:error, "must include a host"}

      {:ok, %URI{userinfo: userinfo}} when not is_nil(userinfo) ->
        {:error, "must not include a username or password"}

      {:ok, %URI{host: host}} ->
        validate_host(host, opts)

      {:error, _part} ->
        {:error, "is not a valid URL"}
    end
  end

  defp validate_host(host, opts) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        if allowed?(address, opts), do: :ok, else: {:error, "must not be a private or reserved address"}

      {:error, :einval} ->
        :ok
    end
  end

  @doc """
  The address a delivery to `url` should connect to.

  `{:ok, nil}` means connect however the HTTP client normally would, which is
  what happens when private destinations are allowed. Otherwise the host is
  resolved and `{:ok, address}` is a public address it resolved to; the
  delivery must connect to that address while keeping the host name for TLS
  and the `Host` header.

  ## Options

    * `:allow_private` — overrides the instance setting, for tests.
  """
  @spec resolve(String.t(), keyword()) :: {:ok, :inet.ip_address() | nil} | {:error, String.t()}
  def resolve(url, opts \\ []) do
    if allow_private?(opts) do
      {:ok, nil}
    else
      url |> URI.parse() |> Map.fetch!(:host) |> resolve_host(opts)
    end
  end

  defp resolve_host(host, opts) do
    case addresses(host) do
      [] ->
        {:error, "could not resolve #{host}"}

      addresses ->
        # Every address, not just the one connected to: a host that resolves
        # to a mix of public and private addresses is somebody probing.
        if Enum.all?(addresses, &allowed?(&1, opts)) do
          {:ok, preferred(addresses)}
        else
          {:error, "#{host} resolves to a private or reserved address"}
        end
    end
  end

  defp addresses(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, address} ->
        [address]

      {:error, :einval} ->
        for family <- [:inet, :inet6],
            {:ok, found} <- [:inet.getaddrs(charlist, family, @resolve_timeout)],
            address <- found,
            uniq: true,
            do: address
    end
  end

  # IPv4 first: an instance without IPv6 egress is the more common way for a
  # dual-stack receiver to be unreachable.
  defp preferred(addresses) do
    Enum.find(addresses, &(tuple_size(&1) == 4)) || hd(addresses)
  end

  @doc """
  Whether a delivery may connect to `address`.
  """
  @spec allowed?(:inet.ip_address(), keyword()) :: boolean()
  def allowed?(address, opts \\ []) do
    allow_private?(opts) or not blocked?(address)
  end

  defp blocked?({_, _, _, _} = address) do
    Enum.any?(@blocked_ipv4, fn {network, prefix} -> in_network?(address, network, prefix, 8) end)
  end

  defp blocked?({_, _, _, _, _, _, _, _} = address) do
    case embedded_ipv4(address) do
      nil -> Enum.any?(@blocked_ipv6, fn {network, prefix} -> in_network?(address, network, prefix, 16) end)
      ipv4 -> blocked?(ipv4)
    end
  end

  # IPv6 addresses that stand for an IPv4 one, and would reach it: IPv4-mapped
  # (::ffff:a.b.c.d), NAT64 (64:ff9b::a.b.c.d) and 6to4 (2002::/16, with the
  # IPv4 address in the 32 bits after the prefix).
  defp embedded_ipv4({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: ipv4(high, low)
  defp embedded_ipv4({0x64, 0xFF9B, 0, 0, 0, 0, high, low}), do: ipv4(high, low)
  defp embedded_ipv4({0x2002, high, low, _, _, _, _, _}), do: ipv4(high, low)
  defp embedded_ipv4(_address), do: nil

  defp ipv4(high, low), do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp in_network?(address, network, prefix, bits_per_part) do
    size = tuple_size(address) * bits_per_part
    shift = size - prefix

    to_integer(address, bits_per_part) >>> shift == to_integer(network, bits_per_part) >>> shift
  end

  defp to_integer(address, bits_per_part) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> (acc <<< bits_per_part) + part end)
  end

  defp allow_private?(opts) do
    Keyword.get_lazy(opts, :allow_private, fn ->
      :nerves_hub
      |> Application.get_env(NervesHub.Webhooks, [])
      |> Keyword.get(:allow_private_destinations, false)
    end)
  end
end
