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

  There is no fallback rule. Every action behind `plug(Attack, ...)` needs a
  rule of its own below, and one without it is not limited at all. A test
  (`AttackTest`) fails when a listed action has no rule.
  """

  use PlugAttack

  alias NervesHub.PlugAttack.Storage
  alias NervesHubWeb.Helpers.ClientIP
  alias PlugAttack.Storage.Ets

  if Mix.env() != :test do
    # Resolved rather than `conn.remote_ip`, or a balancer connecting over
    # loopback would exempt everything that came through it.
    rule "allow local", conn do
      allow(client_ip(conn) == {127, 0, 0, 1})
    end
  end

  # Starting a CLI login and polling one each have an allowance of their own,
  # because nh polls every two seconds while it waits and a shared allowance
  # would leave nothing for a second login from the same address or a poll that
  # arrives a little early.
  rule "throttle CLI logins by ip", conn do
    if conn.private[:phoenix_action] == :cli_session do
      cli_login_throttle(client_ip(conn))
    end
  end

  rule "throttle CLI login polling by ip", conn do
    if conn.private[:phoenix_action] == :check_cli_session do
      cli_poll_throttle(client_ip(conn))
    end
  end

  @doc """
  Limits how many CLI logins one address can start: ten every ten minutes.

  Starting one needs no account, and each login waits five minutes in a table
  that every web node keeps a copy of. Without a limit, one caller could grow
  that table on every node for as long as they kept asking. Someone at a
  terminal starts a login or two.

  Counted on this node only, like `cli_code_throttle/2`, so an address gets the
  limit once per web node. That still bounds it, and a web node still running
  an older release has nothing to do with a count it has never heard of.
  """
  @spec cli_login_throttle(term(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def cli_login_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:cli_login, ip}, time: time, limit: 10, period: to_timeout(minute: 10))
  end

  @doc """
  Limits how often one address can poll CLI logins: 120 times a minute.

  nh polls every two seconds for the five minutes a login waits, which is 30 a
  minute, so this lets four people behind one address log in at once, or one
  CLI poll twice as fast, before any of them is refused.

  Counted per address, not per login token. The token is in the path, so a
  caller making tokens up would get a fresh allowance, and add a row to the
  rate limit table, with each one. Polling a token is how a login is collected,
  but a real one is a random UUID (122 random bits), so guessing at 120 a
  minute, even on every web node at once, never finds one.

  Counted on this node only, like `cli_login_throttle/2`. What a flood of polls
  would wear out is this node's `NervesHub.CLISessionCache` process, which
  every poll calls, and a node is only spared that by a count of its own.
  """
  @spec cli_poll_throttle(term(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def cli_poll_throttle(ip, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:cli_poll, ip}, time: time, limit: 120, period: to_timeout(minute: 1))
  end

  @doc """
  Limits how many CLI login codes one user can try: ten every ten minutes.

  A login is found by its code alone, so without a limit someone signed in could
  guess codes until they confirmed somebody else's CLI into their own account.
  Finding a login and confirming it count one each.

  Counted on this node only. A user's tries spread across the web nodes get the
  limit once per node, which still leaves guessing one of 90 million codes
  pointless.
  """
  @spec cli_code_throttle(pos_integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def cli_code_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:cli_code, user_id}, time: time, limit: 10, period: to_timeout(minute: 10))
  end

  @doc """
  Limits how many two-factor codes can be tried for one user signing in: five
  every ten minutes.

  Three six digit codes work at any moment (this period's and its
  neighbours'), so a guess has about a one in 330,000 chance, and getting to
  guess at all takes the user's password. Recovery codes count against the
  same limit.

  Counted on this node only, like `cli_code_throttle/2`.
  """
  @spec two_factor_throttle(pos_integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def two_factor_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:two_factor, user_id}, time: time, limit: 5, period: to_timeout(minute: 10))
  end

  @doc """
  Limits how many times one user can try a code, or their password, on their
  account's two-factor page: five every ten minutes.

  Turning two-factor off and making new recovery codes ask for a code so that
  a signed in browser alone can't do either. Without a limit, whoever holds
  that browser could guess codes until one worked.

  Counted apart from `two_factor_throttle/2`, so tries here can't lock the
  user out of signing in, and on this node only, like it.
  """
  @spec two_factor_change_throttle(pos_integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def two_factor_change_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:two_factor_change, user_id}, time: time, limit: 5, period: to_timeout(minute: 10))
  end

  @doc """
  Limits how often one signed in user can try to prove it's them: five tries
  every ten minutes.

  Shared by the password and two-factor code on `/account/confirm` and the
  current password on the account page, so whoever holds the browser can't
  guess at one to get round the limit on another. Counted on this node only,
  like `cli_code_throttle/2`.
  """
  @spec confirm_identity_throttle(pos_integer(), keyword()) :: {:allow | :block, {:throttle, keyword()}}
  def confirm_identity_throttle(user_id, opts \\ []) do
    time = opts[:time] || System.system_time(:millisecond)

    do_throttle({:confirm_identity, user_id}, time: time, limit: 5, period: to_timeout(minute: 10))
  end

  @doc """
  Refuses a throttled request with `429 Too Many Requests`, and a `Retry-After`
  of the seconds until its count starts again, so a CLI can wait that long
  rather than give up. A block that isn't a throttle has no count to wait out,
  so it gets the 429 without a `Retry-After`.
  """
  @impl PlugAttack
  def block_action(conn, {:throttle, data}, _opts) do
    retry_after = max(div(data[:expires_at] - System.system_time(:millisecond) + 999, 1000), 1)

    conn
    |> Plug.Conn.put_resp_header("retry-after", Integer.to_string(retry_after))
    |> too_many_requests()
  end

  def block_action(conn, _data, _opts), do: too_many_requests(conn)

  defp too_many_requests(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(:too_many_requests, Jason.encode!(%{errors: %{detail: "Too many requests"}}))
    |> Plug.Conn.halt()
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
