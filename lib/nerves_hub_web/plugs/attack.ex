defmodule NervesHubWeb.Plugs.Attack do
  use PlugAttack

  alias NervesHub.PlugAttack.Storage
  alias NervesHubWeb.RateLimitPubSub
  alias PlugAttack.Storage.Ets

  if Mix.env() != :test do
    rule "allow local", conn do
      allow(conn.remote_ip == {127, 0, 0, 1})
    end
  end

  rule "throttle by ip", conn do
    ip_throttle(conn.remote_ip)
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
end
