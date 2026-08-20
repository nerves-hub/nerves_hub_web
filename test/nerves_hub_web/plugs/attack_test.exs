defmodule NervesHubWeb.Plugs.AttackTest do
  # Rate limit buckets live in one ETS table for the node, and these tests move
  # endpoint config, so they can't share the node with anything else.
  use NervesHubWeb.ConnCase, async: false

  alias NervesHubWeb.Plugs.Attack

  @limit 30

  describe "behind a trusted proxy" do
    setup do: put_endpoint_config(behind_trusted_proxy: true, forwarded_ip_header: "x-forwarded-for")

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
      conn = fn -> Plug.Test.conn(:get, "/") |> Map.put(:remote_ip, {203, 0, 113, 12}) end

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
        behind_trusted_proxy: true,
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
    setup do: put_endpoint_config(behind_trusted_proxy: false, forwarded_ip_header: "x-forwarded-for")

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
  end

  defp exhaust(announced) do
    for _ <- 1..@limit, do: Attack.call(request_from(announced), Attack.init([]))
  end

  defp blocked?(conn), do: Attack.call(conn, Attack.init([])).halted
end
