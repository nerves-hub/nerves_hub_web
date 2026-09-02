defmodule NervesHub.Extensions.LoggingTest do
  @moduledoc """
  What a device may send, and what the platform keeps.

  Not async: these write to `NervesHub.AnalyticsRepo`, and ClickHouse does not
  take concurrent writes.
  """
  use ExUnit.Case, async: false

  alias NervesHub.Analytics.Buffer
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.Device
  alias NervesHub.Devices.LogLine
  alias NervesHub.Devices.LogLines
  alias NervesHub.Extensions
  alias NervesHub.Extensions.Logging
  alias NervesHub.Extensions.Logging.Batched
  alias NervesHub.Extensions.State
  alias NervesHub.Extensions.Unsupported

  describe "which extension a device gets" do
    test "the version it declared decides" do
      assert Extensions.module(:logging, Version.parse!("0.0.1")) == Logging
      assert Extensions.module(:logging, Version.parse!("0.1.0")) == Batched
    end

    test "a version this platform does not implement is not attached at all" do
      # Rather than attached and handed to whichever module was closest. A
      # device that is told logging is off can report that; one whose lines go
      # to a module that cannot read them has no idea.
      assert Extensions.module(:logging, Version.parse!("0.2.0")) == Unsupported
      assert Extensions.module(:logging, Version.parse!("1.0.0")) == Unsupported
    end
  end

  describe "handle_in/3 send, one line at a time" do
    test "stores a single line, which is all a 0.0.x device sends" do
      device = device()

      {_state, []} =
        Logging.handle_in("send", line("hello"), state(device))

      assert ["hello"] = messages(device)
    end

    test "a device that sends too often is still cut off" do
      # The budget is per message, so it is the same budget either version of
      # the extension draws on.
      device = device()
      state = state(device)

      for line <- 1..30 do
        {_state, []} = Logging.handle_in("send", line("#{line}"), state)
      end

      stored = messages(device)

      assert length(stored) < 30, "the rate limit let everything through"
      assert length(stored) >= 5, "the rate limit let almost nothing through"
    end
  end

  describe "handle_in/3 send, a batch at a time" do
    test "stores every line of a batch, in the order the device wrote them" do
      device = device()

      {_state, []} =
        Batched.handle_in("send", %{"lines" => lines(["one", "two", "three"])}, state(device))

      assert ["one", "two", "three"] = messages(device)
    end

    test "a batch costs one message, not one per line" do
      # The point of the whole thing. The limiter allows a burst of 10
      # messages, so 3 batches get through where 60 single lines would have
      # lost all but the first 10.
      device = device()
      state = state(device)

      for batch <- 1..3 do
        {_state, []} =
          Batched.handle_in(
            "send",
            %{"lines" => lines(Enum.map(1..20, &"batch #{batch} line #{&1}"))},
            state
          )
      end

      assert length(messages(device)) == 60
    end

    test "an empty batch is not charged for" do
      # The limiter allows a burst of 10 messages. Ten empty batches would
      # spend all of it, and the lines that followed would be dropped for a
      # device that had not managed to say anything yet.
      device = device()
      state = state(device)

      for _ <- 1..10 do
        {_state, []} = Batched.handle_in("send", %{"lines" => []}, state)
      end

      {_state, []} = Batched.handle_in("send", %{"lines" => lines(["after the empties"])}, state)

      assert messages(device) == ["after the empties"]
    end

    test "a batch past the cap keeps what fits and records the gap" do
      device = device()
      over = Batched.max_lines_per_message() + 20

      {_state, []} =
        Batched.handle_in("send", %{"lines" => lines(Enum.map(1..over, &"line #{&1}"))}, state(device))

      stored = messages(device)

      # Everything up to the cap, plus one line saying what did not fit. A gap
      # someone can see beats a gap they cannot.
      assert length(stored) == Batched.max_lines_per_message() + 1
      assert "line 1" in stored
      assert "line #{Batched.max_lines_per_message()}" in stored

      assert Enum.any?(stored, &String.contains?(&1, "NervesHub dropped 20 log lines")),
             "nothing recorded the 20 lines that were dropped"
    end

    test "a single line from a device that declared 0.1.0 is not a crash" do
      # It is a client that declared a version it does not speak. Worth a line
      # in the platform's own log, not worth taking the connection's extension
      # dispatch through Sentry.
      device = device()

      assert {_state, []} = Batched.handle_in("send", line("hello"), state(device))
      assert messages(device) == []
    end

    test "one unusable line does not take its neighbours with it" do
      device = device()

      {_state, []} =
        Batched.handle_in(
          "send",
          %{"lines" => [line("before"), %{"level" => "info"}, line("after")]},
          state(device)
        )

      assert ["before", "after"] = messages(device)
    end
  end

  # A device id nothing else shares, so the rate limiter's bucket and the stored
  # rows both belong to this test alone.
  #
  # Unique across runs as well as within one. ClickHouse keeps what a previous
  # run wrote and `unique_integer/1` starts counting again each time, so an id
  # from this run can land on rows the last one left behind -- which reads as a
  # test asserting on lines it never sent.
  defp device() do
    id = System.os_time(:second) * 1_000_000_000 + System.unique_integer([:positive])

    %Device{id: id, product_id: id}
  end

  defp state(device) do
    State.new(%DeviceInfo{device_id: device.id, org_id: 1, product_id: device.product_id})
  end

  defp lines(messages), do: Enum.map(messages, &line/1)

  # `meta.time` is where every client puts the timestamp, and a line without
  # one is refused, so a test payload without one would be testing nothing.
  defp line(message) do
    %{
      "level" => "info",
      "message" => message,
      "meta" => %{"time" => "#{System.os_time(:microsecond)}"}
    }
  end

  defp messages(device) do
    :ok = Buffer.flush(LogLine)

    device
    |> LogLines.for_device(limit: 1_000, order: :asc)
    |> Enum.map(& &1.message)
  end
end
