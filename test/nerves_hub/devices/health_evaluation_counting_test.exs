defmodule NervesHub.Devices.HealthEvaluationCountingTest do
  # The pure counting core of health evaluation: in-hand samples counted into
  # windows, counts judged against thresholds, judgements summarized. The
  # same semantics against stored (ClickHouse-counted) readings are pinned in
  # `NervesHub.Devices.HealthEvaluationTest`.
  use ExUnit.Case, async: true

  alias NervesHub.Devices.HealthEvaluation
  alias NervesHub.Products.HealthProfileMetric

  # A fixed minute bucket, so windows are deterministic.
  @now 29_805_720

  defp metric(attrs \\ []) do
    struct!(
      %HealthProfileMetric{
        key: "cpu",
        built_in: false,
        operator: :gte,
        warning_threshold: 80.0,
        warning_period_seconds: 3600,
        alert_threshold: 90.0,
        alert_period_seconds: 3600
      },
      attrs
    )
  end

  # A sample `minutes_ago` whole minutes before @now.
  defp sample(key, value, minutes_ago \\ 0) do
    {key, DateTime.from_unix!((@now - minutes_ago) * 60), value}
  end

  defp judge(metrics, samples, now_minute \\ @now) do
    metrics
    |> HealthEvaluation.judge_metrics(HealthEvaluation.count_samples(metrics, samples, now_minute))
    |> HealthEvaluation.summarize()
  end

  describe "the majority vote" do
    test "no samples means no opinion" do
      assert {:unknown, nil} = judge([metric()], [])
    end

    test "a single healthy sample is healthy" do
      assert {:healthy, nil} = judge([metric()], [sample("cpu", 20.0)])
    end

    test "below half the votes nothing engages; at half it does" do
      below_majority = [sample("cpu", 85.0), sample("cpu", 20.0), sample("cpu", 30.0)]
      assert {:healthy, nil} = judge([metric()], below_majority)

      at_majority = [sample("cpu", 85.0) | below_majority]
      assert {:warning, reasons} = judge([metric()], at_majority)
      assert reasons.warning["cpu"].value == 50
    end

    test "one absurd glitch reading is one vote, not a poisoned window" do
      # A mean over this window would sit in the thousands for as long as
      # the reading stays in it; one vote out of three engages nothing.
      samples = [sample("cpu", 30.0, 10), sample("cpu", 17_000.0, 5), sample("cpu", 31.0)]

      assert {:healthy, nil} = judge([metric()], samples)
    end

    test "an alert majority reports :unhealthy with the full reason" do
      assert {:unhealthy, reasons} = judge([metric()], [sample("cpu", 95.0)])

      assert reasons.unhealthy == %{
               "cpu" => %{value: 100, threshold: 90.0, operator: :gte, period_seconds: 3600, aggregation: :share}
             }
    end
  end

  describe "windows" do
    test "a sample outside the measurement period counts for nothing" do
      assert {:unknown, nil} = judge([metric()], [sample("cpu", 95.0, 90)])
    end

    test "the current, still-filling minute counts" do
      assert {:unhealthy, _} = judge([metric()], [sample("cpu", 95.0, 0)])
    end

    test "old votes age out as the judging minute advances" do
      samples = [
        sample("cpu", 20.0, 55),
        sample("cpu", 20.0, 55),
        sample("cpu", 20.0, 55),
        sample("cpu", 85.0, 30),
        sample("cpu", 85.0, 29)
      ]

      # Two breaching of five is short of a majority now; once the three low
      # samples fall out of the hour window, two of two engages — with no new
      # sample arriving. (This is why an all-clear report is not a safe
      # reason to skip evaluation.)
      assert {:healthy, nil} = judge([metric()], samples)
      assert {:warning, _} = judge([metric()], samples, @now + 26)
    end

    test "warning and alert windows are separate" do
      short_alert = metric(alert_period_seconds: 600)

      # In the hour-long warning window but outside the ten-minute alert
      # window: the sample can only engage the warning level.
      assert {:warning, _} = judge([short_alert], [sample("cpu", 95.0, 30)])
    end
  end

  describe "what gets counted" do
    test "keys outside the profile and non-number values are ignored" do
      samples = [sample("other", 100.0), sample("cpu", "hot")]

      assert {:unknown, nil} = judge([metric()], samples)
    end

    test "each metric is judged on its own samples" do
      metrics = [metric(), metric(key: "mem", warning_threshold: 70.0, alert_threshold: 80.0)]
      samples = [sample("cpu", 85.0), sample("mem", 95.0)]

      assert {:unhealthy, reasons} = judge(metrics, samples)
      assert %{"mem" => _} = reasons.unhealthy
      assert %{"cpu" => _} = reasons.warning
    end
  end

  describe "a low-is-unhealthy metric" do
    defp fps() do
      metric(
        key: "fps",
        operator: :lte,
        warning_threshold: 25.0,
        warning_period_seconds: 3600,
        alert_threshold: 15.0,
        alert_period_seconds: 3600
      )
    end

    test "engages under the thresholds, not over them" do
      assert {:healthy, nil} = judge([fps()], [sample("fps", 30.0)])
      assert {:warning, reasons} = judge([fps()], [sample("fps", 20.0)])
      assert reasons.warning["fps"].operator == :lte

      assert {:unhealthy, reasons} = judge([fps()], [sample("fps", 10.0)])
      assert reasons.unhealthy["fps"].threshold == 15.0
    end

    test "the majority rule flips direction with the operator" do
      assert {:healthy, nil} = judge([fps()], [sample("fps", 60.0), sample("fps", 0.0), sample("fps", 59.0)])

      low_half = [sample("fps", 20.0), sample("fps", 60.0), sample("fps", 20.0), sample("fps", 60.0)]
      assert {:warning, _} = judge([fps()], low_half)
    end
  end

  describe "merge_counts/2" do
    test "adds stored counts and in-hand counts per level" do
      stored = %{"cpu" => %{warning: {3, 1}, alert: {3, 0}}}
      in_hand = HealthEvaluation.count_samples([metric()], [sample("cpu", 85.0)], @now)

      assert HealthEvaluation.merge_counts(stored, in_hand) ==
               %{"cpu" => %{warning: {4, 2}, alert: {4, 0}}}
    end

    test "keys missing on either side pass through" do
      stored = %{"cpu" => %{warning: {1, 0}, alert: {1, 0}}}
      in_hand = %{"mem" => %{warning: {1, 1}, alert: {1, 1}}}

      merged = HealthEvaluation.merge_counts(stored, in_hand)
      assert merged["cpu"] == %{warning: {1, 0}, alert: {1, 0}}
      assert merged["mem"] == %{warning: {1, 1}, alert: {1, 1}}
    end
  end

  describe "summarize/1" do
    test "alert wins over warning, healthy beats no data, reasons name every engaged metric" do
      assert {:unknown, nil} = HealthEvaluation.summarize([:unknown, :unknown])
      assert {:healthy, nil} = HealthEvaluation.summarize([:unknown, :healthy])

      judgements = [
        :healthy,
        {:warning, "cpu", %{value: 50}},
        {:unhealthy, "mem", %{value: 100}}
      ]

      assert {:unhealthy, reasons} = HealthEvaluation.summarize(judgements)
      assert reasons == %{warning: %{"cpu" => %{value: 50}}, unhealthy: %{"mem" => %{value: 100}}}
    end
  end
end
