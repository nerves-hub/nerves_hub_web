defmodule NervesHub.Devices.HealthEvaluation.WindowsTest do
  use ExUnit.Case, async: true

  alias NervesHub.Devices.HealthEvaluation.Windows
  alias NervesHub.Products.HealthProfile
  alias NervesHub.Products.HealthProfileMetric

  # Pure structs, no database: warning at 80 over an hour, alert at 90 over
  # 10 minutes, so the two levels read different windows.
  defp profile(overrides \\ %{}) do
    metric =
      Map.merge(
        %HealthProfileMetric{
          key: "cpu",
          built_in: false,
          warning_threshold: 80.0,
          warning_period_seconds: 3600,
          alert_threshold: 90.0,
          alert_period_seconds: 600
        },
        overrides
      )

    %HealthProfile{id: 1, product_id: 1, platform: nil, metrics: [metric]}
  end

  defp judge(windows, profile, minute) do
    windows |> Windows.judge(profile, minute) |> Windows.summarize()
  end

  # An arbitrary but fixed current minute.
  @now 29_000_000

  describe "the counting rule" do
    test "no samples is no opinion" do
      assert {:unknown, nil} = judge(Windows.new(), profile(), @now)
    end

    test "a lone sample at the threshold engages" do
      windows = Windows.record(Windows.new(), profile(), %{"cpu" => 80.0}, @now)

      assert {:warning, reasons} = judge(windows, profile(), @now)

      assert reasons.warning == %{
               "cpu" => %{value: 100, threshold: 80.0, operator: :gte, period_seconds: 3600, aggregation: :share}
             }
    end

    test "half the samples at or over the threshold engages, less does not" do
      p = profile()

      below_majority =
        Enum.reduce([85.0, 20.0, 30.0], Windows.new(), &Windows.record(&2, p, %{"cpu" => &1}, @now))

      assert {:healthy, nil} = judge(below_majority, p, @now)

      at_majority = Windows.record(below_majority, p, %{"cpu" => 85.0}, @now)

      assert {:warning, %{warning: %{"cpu" => %{value: 50}}}} = judge(at_majority, p, @now)
    end

    test "one absurd glitch reading is one vote, not a value" do
      p = profile()

      windows =
        Enum.reduce([30.0, 17_000.0, 31.0], Windows.new(), &Windows.record(&2, p, %{"cpu" => &1}, @now))

      assert {:healthy, nil} = judge(windows, p, @now)
    end

    test "warning and alert read their own windows" do
      p = profile()

      # An alert-level sample 30 minutes ago: outside the 10-minute alert
      # window, inside the hour-long warning window.
      windows = Windows.record(Windows.new(), p, %{"cpu" => 95.0}, @now - 30)

      assert {:warning, reasons} = judge(windows, p, @now)
      assert %{"cpu" => %{threshold: 80.0}} = reasons.warning

      # The same sample fresh engages the alert.
      windows = Windows.record(Windows.new(), p, %{"cpu" => 95.0}, @now)

      assert {:unhealthy, %{unhealthy: %{"cpu" => %{threshold: 90.0}}}} = judge(windows, p, @now)
    end

    test "keys outside the profile and non-numbers are not counted" do
      p = profile()

      windows = Windows.record(Windows.new(), p, %{"other" => 100.0, "cpu" => "hot"}, @now)

      assert windows == %{}
    end
  end

  # A frame rate: warning at or under 25 over an hour, alert at or under 15
  # over 10 minutes.
  defp fps_profile() do
    profile(%{key: "fps", operator: :lte, warning_threshold: 25.0, alert_threshold: 15.0})
  end

  describe "a low-is-unhealthy metric (operator :lte)" do
    test "engages as the value drops, with the direction in the reason" do
      p = fps_profile()

      assert {:healthy, nil} = judge(Windows.record(Windows.new(), p, %{"fps" => 30.0}, @now), p, @now)

      assert {:warning, reasons} = judge(Windows.record(Windows.new(), p, %{"fps" => 20.0}, @now), p, @now)

      assert reasons.warning == %{
               "fps" => %{value: 100, threshold: 25.0, operator: :lte, period_seconds: 3600, aggregation: :share}
             }

      assert {:unhealthy, %{unhealthy: %{"fps" => %{threshold: 15.0, operator: :lte}}}} =
               judge(Windows.record(Windows.new(), p, %{"fps" => 10.0}, @now), p, @now)
    end

    test "one glitched zero reading is one vote, not a trip" do
      p = fps_profile()

      windows =
        Enum.reduce([60.0, 0.0, 59.0], Windows.new(), &Windows.record(&2, p, %{"fps" => &1}, @now))

      assert {:healthy, nil} = judge(windows, p, @now)
    end

    test "half the samples at or under the threshold engages" do
      p = fps_profile()

      windows =
        Enum.reduce([20.0, 60.0, 20.0, 60.0], Windows.new(), &Windows.record(&2, p, %{"fps" => &1}, @now))

      assert {:warning, %{warning: %{"fps" => %{value: 50}}}} = judge(windows, p, @now)
    end
  end

  describe "time passing" do
    test "samples aging out can raise the status - the case a naive screen misses" do
      p = profile()

      # Two low samples early, then two high ones: 2 of 4 at/over already
      # engages under the counting rule, so start below that with three low.
      windows =
        Windows.new()
        |> Windows.record(p, %{"cpu" => 20.0}, @now - 55)
        |> Windows.record(p, %{"cpu" => 20.0}, @now - 55)
        |> Windows.record(p, %{"cpu" => 20.0}, @now - 55)
        |> Windows.record(p, %{"cpu" => 85.0}, @now - 30)
        |> Windows.record(p, %{"cpu" => 85.0}, @now - 29)

      assert {:healthy, nil} = judge(windows, p, @now)

      # Ten minutes later the low samples have left the hour window and the
      # high pair is the majority of what remains.
      later = @now + 10
      windows = Windows.prune(windows, p, later)

      assert {:warning, %{warning: %{"cpu" => %{value: 100}}}} = judge(windows, p, later)
    end

    test "samples aging out can clear the status" do
      p = profile()

      windows = Windows.record(Windows.new(), p, %{"cpu" => 95.0}, @now)

      assert {:unhealthy, _} = judge(windows, p, @now)

      # Out of the 10-minute alert window but still in the warning hour.
      assert {:warning, _} = judge(windows, p, @now + 15)

      # Out of every window: pruned away entirely, and no opinion remains.
      later = @now + 61
      assert Windows.prune(windows, p, later) == %{}
      assert {:unknown, nil} = judge(Windows.prune(windows, p, later), p, later)
    end

    test "prune drops keys no longer in the profile" do
      p = profile()
      windows = Windows.record(Windows.new(), p, %{"cpu" => 50.0}, @now)

      renamed = %{p | metrics: [%{hd(p.metrics) | key: "cpu_temp"}]}

      assert Windows.prune(windows, renamed, @now) == %{}
    end
  end

  describe "from_samples/3" do
    test "rebuilds windows, ignoring samples older than the longest window" do
      p = profile()
      now = DateTime.utc_now()
      now_minute = Windows.minute(now)

      samples = [
        {"cpu", DateTime.add(now, -30, :minute), 85.0},
        {"cpu", DateTime.add(now, -90, :minute), 20.0},
        {"other", now, 100.0}
      ]

      windows = Windows.from_samples(p, samples, now_minute)

      # Only the in-window cpu sample: one sample, at/over warning.
      assert {:warning, %{warning: %{"cpu" => %{value: 100}}}} = judge(windows, p, now_minute)
    end
  end

  describe "summarize/1" do
    test "alert wins over warning, healthy beats no data" do
      reason = %{value: 100, threshold: 1.0, period_seconds: 60, aggregation: :share}

      assert {:unhealthy, %{warning: %{"a" => _}, unhealthy: %{"b" => _}}} =
               Windows.summarize([{:warning, "a", reason}, {:unhealthy, "b", reason}, :healthy, :unknown])

      assert {:healthy, nil} = Windows.summarize([:unknown, :healthy])
      assert {:unknown, nil} = Windows.summarize([:unknown])
      assert {:unknown, nil} = Windows.summarize([])
    end
  end
end
