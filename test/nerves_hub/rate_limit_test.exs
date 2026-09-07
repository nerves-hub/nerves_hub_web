defmodule NervesHub.RateLimitTest do
  use ExUnit.Case, async: false

  alias NervesHub.RateLimit

  # The bucket is global and keyed by the current second, and these tests
  # deliberately fill it past the limit. Clearing it on the way out as well as
  # on the way in keeps the next test in the same second from being rejected by
  # `NervesHub.DeviceSSLTransport`, which reads the same counter.
  setup do
    :ets.delete_all_objects(:nerves_hub_rate_limit)
    on_exit(fn -> :ets.delete_all_objects(:nerves_hub_rate_limit) end)
    :ok
  end

  test "increment/0 returns true when under the limit" do
    assert RateLimit.increment() == true
  end

  test "increment/0 returns false when the limit is exceeded" do
    limit = Application.get_env(:nerves_hub, RateLimit)[:limit]

    for _ <- 1..limit do
      RateLimit.increment()
    end

    assert RateLimit.increment() == false
  end

  test "multiple calls within the same second share the same bucket and accumulate" do
    limit = Application.get_env(:nerves_hub, RateLimit)[:limit]

    results = for _ <- 1..limit, do: RateLimit.increment()

    assert Enum.all?(results, & &1)
    assert RateLimit.increment() == false
  end
end
