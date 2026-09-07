defmodule NervesHub.ErrorReports.PayloadTest do
  use ExUnit.Case, async: true

  alias NervesHub.ErrorReports.Payload

  defp valid(overrides \\ %{}) do
    Map.merge(
      %{
        "timestamp" => "2026-08-31T10:22:31.123456Z",
        "kind" => "error",
        "reason" => "** (RuntimeError) boom"
      },
      overrides
    )
  end

  describe "required fields" do
    test "a report with everything is accepted" do
      assert {:ok, attrs} = Payload.normalize(valid())
      assert attrs.timestamp == ~U[2026-08-31 10:22:31.123456Z]
      assert attrs.kind == "error"
      assert attrs.reason == "** (RuntimeError) boom"
    end

    test "a missing timestamp is refused rather than stamped on arrival" do
      assert {:error, :missing_timestamp} = Payload.normalize(Map.delete(valid(), "timestamp"))
    end

    test "an unparseable timestamp is refused" do
      assert {:error, :missing_timestamp} = Payload.normalize(valid(%{"timestamp" => "yesterday"}))
    end

    test "a missing kind is refused" do
      assert {:error, :missing_kind} = Payload.normalize(Map.delete(valid(), "kind"))
    end

    test "a missing reason is refused" do
      assert {:error, :missing_reason} = Payload.normalize(Map.delete(valid(), "reason"))
    end

    test "something that is not a map is refused rather than raising" do
      assert {:error, :malformed} = Payload.normalize("nope")
      assert {:error, :malformed} = Payload.normalize(nil)
    end
  end

  describe "timestamps" do
    test "a DateTime is taken as it is" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"timestamp" => ~U[2026-01-01 00:00:00Z]}))
      assert attrs.timestamp == ~U[2026-01-01 00:00:00Z]
    end

    # The shape every existing client already uses for log lines.
    test "meta.time in microseconds is accepted" do
      report = valid(%{"meta" => %{"time" => "1756636951123456"}}) |> Map.delete("timestamp")

      assert {:ok, attrs} = Payload.normalize(report)
      assert attrs.timestamp == DateTime.from_unix!(1_756_636_951_123_456, :microsecond)
    end

    test "a meta.time that is not a number is refused" do
      report = valid(%{"meta" => %{"time" => "soon"}}) |> Map.delete("timestamp")

      assert {:error, :missing_timestamp} = Payload.normalize(report)
    end
  end

  describe "caps" do
    test "frames past the limit are dropped and the report is marked truncated" do
      frames = for i <- 1..(Payload.max_frames() + 5), do: %{"module" => "M#{i}"}

      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => frames}))
      assert length(attrs.frames) == Payload.max_frames()
      assert attrs.truncated == 1
    end

    test "frames within the limit leave the report untruncated" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => [%{"module" => "M"}]}))
      assert attrs.truncated == 0
    end

    test "an over-long reason is cut and marked" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"reason" => String.duplicate("a", 5_000)}))
      assert byte_size(attrs.reason) == 2_048
      assert attrs.truncated == 1
    end

    test "an over-long message is cut and marked" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"message" => String.duplicate("a", 20_000)}))
      assert byte_size(attrs.message) == 8_192
      assert attrs.truncated == 1
    end

    # Cutting on a byte boundary would split a character and leave a binary
    # ClickHouse accepts and nothing renders.
    test "cutting a multi-byte string leaves valid UTF-8" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"reason" => String.duplicate("é", 3_000)}))
      assert String.valid?(attrs.reason)
      assert byte_size(attrs.reason) <= 2_048
    end

    test "context keys past the limit are dropped and marked" do
      context = for i <- 1..40, into: %{}, do: {"k#{i}", "v"}

      assert {:ok, attrs} = Payload.normalize(valid(%{"context" => context}))
      assert map_size(attrs.context) == 32
      assert attrs.truncated == 1
    end

    test "payload_bytes records the size before anything was cut" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"message" => String.duplicate("a", 20_000)}))
      assert attrs.payload_bytes > 20_000
    end
  end

  describe "context" do
    test "credential-shaped keys are redacted" do
      context = %{"queue" => "uploads", "token" => "sekrit", "password" => "hunter2"}

      assert {:ok, attrs} = Payload.normalize(valid(%{"context" => context}))
      assert attrs.context["queue"] == "uploads"
      assert attrs.context["token"] == "[redacted]"
      assert attrs.context["password"] == "[redacted]"
    end

    test "non-string values become strings, since the column is a string map" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"context" => %{"n" => 5, "on" => true}}))
      assert attrs.context["n"] == "5"
      assert attrs.context["on"] == "true"
    end

    test "a context that is not a map is ignored rather than refused" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"context" => "nope"}))
      assert attrs.context == %{}
    end
  end

  describe "frames" do
    test "fields are picked out and the line is kept as an integer" do
      frame = %{"module" => "M", "function" => "f/1", "file" => "m.ex", "line" => 42}

      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => [frame]}))
      assert attrs.frames == [%{module: "M", function: "f/1", file: "m.ex", line: 42}]
    end

    test "a non-integer line is dropped rather than stored as a string" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => [%{"line" => "42"}]}))
      assert [%{line: nil}] = attrs.frames
    end

    # Dropping it would shift every frame below and change the fingerprint.
    test "a frame that is not a map keeps its position as an empty slot" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => ["junk", %{"module" => "M"}]}))
      assert [%{module: nil}, %{module: "M"}] = attrs.frames
    end

    test "frames that are not a list are ignored" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"frames" => "nope"}))
      assert attrs.frames == []
    end
  end

  describe "other fields" do
    test "an unknown source falls back to logger" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"source" => "whatever"}))
      assert attrs.source == "logger"
    end

    test "manual is kept" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"source" => "manual"}))
      assert attrs.source == "manual"
    end

    # Vitals are context, not fields, so a client with different ones to report
    # needs no change on this side.
    test "device vitals ride along in context, unmodified" do
      context = %{"uptime_ms" => 987_654, "reboot_count" => 3, "rssi_dbm" => -67}

      assert {:ok, attrs} = Payload.normalize(valid(%{"context" => context}))
      assert attrs.context["uptime_ms"] == "987654"
      assert attrs.context["reboot_count"] == "3"
      assert attrs.context["rssi_dbm"] == "-67"
      refute Map.has_key?(attrs, :uptime_ms)
    end

    test "a blank supplied fingerprint is treated as absent" do
      assert {:ok, attrs} = Payload.normalize(valid(%{"fingerprint" => "   "}))
      assert attrs.fingerprint == nil
    end
  end
end
