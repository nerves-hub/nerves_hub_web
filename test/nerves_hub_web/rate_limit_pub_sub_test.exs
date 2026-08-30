defmodule NervesHubWeb.RateLimitPubSubTest do
  use ExUnit.Case, async: true

  alias NervesHubWeb.Plugs.Attack
  alias NervesHubWeb.RateLimitPubSub

  # A unique IP per test keeps each one in its own PlugAttack bucket, so the
  # shared storage and singleton GenServer don't cross-contaminate.
  defp unique_ip() do
    n = System.unique_integer([:positive])
    {10, 0, rem(n, 256), rem(div(n, 256), 256)}
  end

  test "peer-origin throttles increment the shared count; self-origin is skipped" do
    ip = unique_ip()
    time = System.system_time(:millisecond)
    pid = Process.whereis(RateLimitPubSub)

    # Self-origin messages are our own dispatch echoed back and must be ignored —
    # the origin node already incremented inline.
    for _ <- 1..40, do: send(pid, {:throttle, {:ip, ip}, time, node()})
    _ = :sys.get_state(pid)

    # Still allowed: the 40 self-origin messages did not count, so this is the
    # first increment for the bucket.
    assert {:allow, _} = Attack.ip_throttle(ip, time: time)

    # Peer-origin messages DO increment; enough of them cross the limit.
    for _ <- 1..40, do: send(pid, {:throttle, {:ip, ip}, time, :peer@nohost})
    _ = :sys.get_state(pid)

    assert {:block, _} = Attack.ip_throttle(ip, time: time)
  end
end
