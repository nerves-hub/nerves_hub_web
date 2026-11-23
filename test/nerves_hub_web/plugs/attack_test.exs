defmodule NervesHubWeb.Plugs.AttackTest do
  # Rate limit buckets live in one ETS table for the node, and these tests move
  # endpoint config, so they can't share the node with anything else.
  use NervesHubWeb.ConnCase, async: false

  alias NervesHubWeb.Plugs.Attack

  # What one address may do starting a CLI login. Every request these tests send
  # is one, since a request is only limited by the rule for its action.
  @limit 10

  describe "behind a trusted proxy" do
    setup do: put_endpoint_config(rate_limit_by_forwarded_ip: true, forwarded_ip_header: "x-forwarded-for")

    test "buckets by the client the proxy announced rather than the proxy" do
      # Every request arrives from the same proxy. Before this, that made one
      # bucket for the internet.
      exhaust("203.0.113.10")

      refute blocked?(request_from("198.51.100.10"))
    end

    test "still counts a single client across its requests" do
      exhaust("203.0.113.11")

      assert blocked?(request_from("203.0.113.11"))
    end

    test "falls back to the socket when the proxy announced nothing" do
      conn = fn -> :get |> Plug.Test.conn("/") |> Map.put(:remote_ip, {203, 0, 113, 12}) |> cli_login() end

      for _ <- 1..@limit, do: Attack.call(conn.(), Attack.init([]))

      assert blocked?(conn.())
    end
  end

  describe "behind a trusted proxy that appends its own entry" do
    # Fly.io's shape: the address it observed, then the app's own anycast
    # address. Counting from the right without skipping that would put the whole
    # fleet in one bucket, which is the thing being fixed.
    setup do
      put_endpoint_config(
        rate_limit_by_forwarded_ip: true,
        forwarded_ip_header: "x-forwarded-for",
        forwarded_ip_trailing_hops: 1
      )
    end

    test "buckets by the caller rather than by the proxy's own address" do
      for _ <- 1..@limit do
        Attack.call(request_from("203.0.113.20, 66.241.125.59"), Attack.init([]))
      end

      refute blocked?(request_from("198.51.100.20, 66.241.125.59"))
      assert blocked?(request_from("203.0.113.20, 66.241.125.59"))
    end
  end

  describe "without a trusted proxy" do
    setup do: put_endpoint_config(rate_limit_by_forwarded_ip: false, forwarded_ip_header: "x-forwarded-for")

    test "ignores the header, so a caller can't pick its own bucket" do
      # The header is named -- a device's address is still recorded from it --
      # but nothing here is decided on it. A caller rotating the value stays in
      # the one bucket its socket earns.
      for address <- 1..@limit do
        Attack.call(request_from("198.51.100.#{address}"), Attack.init([]))
      end

      assert blocked?(request_from("198.51.100.200"))
    end
  end

  describe "polling a CLI login" do
    test "allows one address 120 polls a minute, counted apart from everything else" do
      ip = {203, 0, 113, 50}
      time = System.system_time(:millisecond)

      for _ <- 1..120, do: assert({:allow, _} = Attack.cli_poll_throttle(ip, time: time))

      assert {:block, {:throttle, data}} = Attack.cli_poll_throttle(ip, time: time)
      assert data[:limit] == 120
      assert data[:remaining] == 0

      # Another address, the next minute, and the login allowance are all
      # untouched.
      assert {:allow, _} = Attack.cli_poll_throttle({203, 0, 113, 51}, time: time)
      assert {:allow, _} = Attack.cli_poll_throttle(ip, time: time + 60_000)
      assert {:allow, {:throttle, login}} = Attack.cli_login_throttle(ip, time: time)
      assert login[:remaining] == @limit - 1
    end

    test "is refused with a 429 and how many seconds to wait" do
      conn =
        Attack.block_action(
          Plug.Test.conn(:get, "/"),
          {:throttle, expires_at: System.system_time(:millisecond) + 12_500},
          []
        )

      assert conn.halted
      assert conn.status == 429
      assert Plug.Conn.get_resp_header(conn, "retry-after") == ["13"]
      assert Jason.decode!(conn.resp_body) == %{"errors" => %{"detail" => "Too many requests"}}
    end

    test "refuses a block that isn't a throttle without a Retry-After" do
      conn = Attack.block_action(Plug.Test.conn(:get, "/"), true, [])

      assert conn.status == 429
      assert Plug.Conn.get_resp_header(conn, "retry-after") == []
    end

    test "never says to retry in less than a second" do
      conn =
        Attack.block_action(
          Plug.Test.conn(:get, "/"),
          {:throttle, expires_at: System.system_time(:millisecond) - 5},
          []
        )

      assert Plug.Conn.get_resp_header(conn, "retry-after") == ["1"]
    end
  end

  describe "every action behind the plug" do
    # There is no fallback rule, so an action added to a controller's
    # `plug(Attack when action in [...])` without a rule of its own would not be
    # limited at all. This finds each one in the controllers' source and checks
    # it gets blocked.
    test "has a rule of its own" do
      actions = attacked_actions()

      assert actions != [], "found no `plug(Attack when action in [...])`"

      for {action, index} <- Enum.with_index(actions) do
        conn = fn ->
          :get
          |> Plug.Test.conn("/")
          |> Map.put(:remote_ip, {203, 0, 113, 100 + index})
          |> Plug.Conn.put_private(:phoenix_action, action)
        end

        # The largest allowance is 120 a minute, so this is past any of them.
        assert Enum.any?(1..200, fn _ -> Attack.call(conn.(), Attack.init([])).halted end),
               "#{inspect(action)} is behind the Attack plug but no rule limits it"
      end
    end
  end

  defp put_endpoint_config(overrides) do
    previous = Application.get_env(:nerves_hub, NervesHubWeb.Endpoint)

    Application.put_env(
      :nerves_hub,
      NervesHubWeb.Endpoint,
      Keyword.merge(previous, overrides)
    )

    on_exit(fn -> Application.put_env(:nerves_hub, NervesHubWeb.Endpoint, previous) end)
  end

  # One socket, many announced clients: the shape every request takes behind a
  # balancer.
  defp request_from(announced) do
    :get
    |> Plug.Test.conn("/")
    |> Map.put(:remote_ip, {10, 0, 0, 1})
    |> Plug.Conn.put_req_header("x-forwarded-for", announced)
    |> cli_login()
  end

  defp cli_login(conn), do: Plug.Conn.put_private(conn, :phoenix_action, :cli_session)

  # Every action named in a `plug(Attack when action in [...])`, read from the
  # controllers. A use of the plug in any other shape fails the test, so it
  # can't slip past it.
  defp attacked_actions() do
    "lib/nerves_hub_web/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      {_ast, found} =
        path
        |> File.read!()
        |> Code.string_to_quoted!()
        |> Macro.prewalk([], fn
          {:plug, _, [{:when, _, [{:__aliases__, _, [:Attack]}, {:in, _, [{:action, _, _}, actions]}]}]} = node, acc
          when is_list(actions) ->
            {node, acc ++ actions}

          {:plug, _, [{:__aliases__, _, [:Attack]} | _]} = node, _acc ->
            flunk("#{path} uses the Attack plug in a shape this test can't read: #{Macro.to_string(node)}")

          {:plug, _, [{:when, _, [{:__aliases__, _, [:Attack]} | _]}]} = node, _acc ->
            flunk("#{path} uses the Attack plug in a shape this test can't read: #{Macro.to_string(node)}")

          node, acc ->
            {node, acc}
        end)

      found
    end)
    |> Enum.uniq()
  end

  defp exhaust(announced) do
    for _ <- 1..@limit, do: Attack.call(request_from(announced), Attack.init([]))
  end

  defp blocked?(conn), do: Attack.call(conn, Attack.init([])).halted
end
