defmodule NervesHubWeb.Plugs.Attack do
  @moduledoc """
  Rate limiting, bucketed by where the request came from.

  Which address that is depends on the deployment. `conn.remote_ip` is the other
  end of the socket, and behind a load balancer that is the balancer itself, so
  every caller in the world shares one bucket and the limit stops being a limit
  on anyone in particular -- it becomes a shared allowance that legitimate
  callers exhaust between them.

  Reading the balancer's forwarded header fixes that, but only where a balancer
  is really there to write it. Nothing stops a caller sending the header itself,
  and a caller that can choose its own bucket has no limit at all. So the header
  is bucketed by only once an operator has turned it on:

      config :nerves_hub, NervesHubWeb.Endpoint, rate_limit_by_forwarded_ip: true

  Off by default, which errs towards the shared bucket: too strict for everyone
  rather than absent for whoever thinks to forge a header.
  """

  use PlugAttack

  alias NervesHub.PlugAttack.Storage
  alias NervesHubWeb.Helpers.ClientIP
  alias NervesHubWeb.RateLimitPubSub
  alias PlugAttack.Storage.Ets

  if Mix.env() != :test do
    # Resolved rather than `conn.remote_ip`, or a balancer connecting over
    # loopback would exempt everything that came through it.
    rule "allow local", conn do
      allow(client_ip(conn) == {127, 0, 0, 1})
    end
  end

  rule "throttle by ip", conn do
    ip_throttle(client_ip(conn))
  end

  def ip_throttle(ip, opts \\ []) do
    key = {:ip, ip}
    time = opts[:time] || System.system_time(:millisecond)
    if !opts[:time], do: RateLimitPubSub.broadcast(key, time)

    do_throttle(key, time: time, limit: 30, period: 60_000)
  end

  defp do_throttle(key, opts) do
    limit = Keyword.fetch!(opts, :limit)
    period = Keyword.fetch!(opts, :period)
    now = Keyword.fetch!(opts, :time)

    expires_at = expires_at(now, period)
    count = Ets.increment(Storage, {:throttle, key, div(now, period)}, 1, expires_at)
    rem = limit - count
    data = [period: period, expires_at: expires_at, limit: limit, remaining: max(rem, 0)]
    {if(rem >= 0, do: :allow, else: :block), {:throttle, data}}
  end

  defp expires_at(now, period), do: (div(now, period) + 1) * period

  defp client_ip(conn) do
    config = Application.get_env(:nerves_hub, endpoint(conn), [])

    if Keyword.get(config, :rate_limit_by_forwarded_ip, false) do
      ClientIP.remote_ip(
        conn,
        Keyword.get(config, :forwarded_ip_header),
        Keyword.get(config, :forwarded_ip_trailing_hops, 0)
      )
    else
      conn.remote_ip
    end
  end

  # The endpoint the request arrived on, since trust is a property of that
  # endpoint rather than of the application.
  defp endpoint(conn), do: conn.private[:phoenix_endpoint] || NervesHubWeb.Endpoint
end
