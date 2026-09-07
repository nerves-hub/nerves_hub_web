defmodule NervesHub.Extensions.JitterTest do
  use ExUnit.Case, async: true

  alias NervesHub.Extensions.Jitter

  @interval to_timeout(minute: 10)

  describe "start_delay/1" do
    test "never exceeds the interval, so the first report is not delayed past one period" do
      for _ <- 1..2_000 do
        delay = Jitter.start_delay(@interval)
        assert delay >= 1
        assert delay <= @interval
      end
    end

    test "spreads a fleet that attaches together across the whole interval" do
      # What a deploy produces: every device attaching inside the same second.
      # Unjittered, all 1500 land on the identical millisecond and stay there,
      # because device connections are long-lived.
      delays = for _ <- 1..1_500, do: Jitter.start_delay(@interval)

      # Concentration, not range: a few outliers can widen the range while the
      # bulk still fires together. Production measured 74% in one 30s bucket.
      bucket = to_timeout(second: 30)
      peak = delays |> Enum.frequencies_by(&div(&1, bucket)) |> Map.values() |> Enum.max()

      assert peak / 1_500 < 0.10, "#{round(peak / 15)}% of devices landed in one 30s bucket"
    end

    test "rejects a non-positive interval rather than arming a nonsense timer" do
      assert_raise FunctionClauseError, fn -> Jitter.start_delay(0) end
      assert_raise FunctionClauseError, fn -> Jitter.start_delay(-5) end
    end
  end
end
