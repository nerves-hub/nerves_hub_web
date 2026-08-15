defmodule NervesHub.RateLimitTest do
  use ExUnit.Case, async: false

  alias NervesHub.RateLimit

  setup do
    # Clear the ETS table between tests so each test starts with an empty bucket
    :ets.delete_all_objects(:nerves_hub_rate_limit)
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

    # All calls so far should be within the limit
    assert Enum.all?(results, & &1)

    # One more call goes over
    assert RateLimit.increment() == false
  end
end
