defmodule NervesHub.RateLimit.FrozenClockTest do
  @moduledoc """
  `NervesHub.DataCase.freeze_rate_limit_clock/1` works only because Hammer
  reads the time from `System.system_time(:second)`. If an upgrade moves that,
  the freeze stops doing anything and the throttle tests that rely on it go
  back to failing now and then, on unrelated changes. This fails straight away
  instead.
  """

  use ExUnit.Case, async: true
  use Mimic

  import NervesHub.DataCase, only: [freeze_rate_limit_clock: 1]

  alias NervesHub.RateLimit.Metrics, as: RateLimit

  setup :freeze_rate_limit_clock

  test "a spent bucket stays spent while the clock is held, and refills when it moves" do
    key = "frozen_clock_test_#{System.unique_integer([:positive])}"

    assert {:allow, 0} = RateLimit.hit(key, 1, 1, 1)
    assert {:deny, _ms} = RateLimit.hit(key, 1, 1, 1)

    next_second = System.system_time(:second) + 1

    stub(System, :system_time, fn
      :second -> next_second
      unit -> call_original(System, :system_time, [unit])
    end)

    # Held, the bucket could only refill if Hammer read some other clock; moved,
    # it refills only because Hammer reads this one.
    assert {:allow, 0} = RateLimit.hit(key, 1, 1, 1)
  end
end
