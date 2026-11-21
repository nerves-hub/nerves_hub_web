defmodule NervesHub.Analytics.BufferTest do
  # Not async: these tests interact with the AnalyticsRepo, which is a ClickHouse
  # database that does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.LogLine

  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  @product_id 1

  setup do
    # The application-wide buffer may still be holding rows from an earlier test.
    :ok = Buffer.flush(LogLine)
    AnalyticsRepo.query!("TRUNCATE TABLE device_log_lines")

    on_exit(fn -> AnalyticsRepo.query!("TRUNCATE TABLE device_log_lines") end)

    :ok
  end

  describe "flushing" do
    test "flush/1 writes everything buffered" do
      buffer = start_buffer(max_batch_size: 1_000, max_delay: to_timeout(minute: 1))

      for n <- 1..50, do: Buffer.insert(buffer, log_line(n))

      # Nothing has been written yet - neither trigger has fired.
      assert messages() == []

      :ok = Buffer.flush(buffer)

      assert length(messages()) == 50
    end

    test "flush/1 on an empty buffer is a no-op" do
      buffer = start_buffer([])

      assert :ok = Buffer.flush(buffer)
      assert messages() == []
    end

    test "a full batch is written without waiting for the delay" do
      buffer = start_buffer(max_batch_size: 5, max_delay: to_timeout(minute: 1))

      for n <- 1..5, do: Buffer.insert(buffer, log_line(n))

      assert_eventually(length(messages()) == 5)
    end

    test "a partial batch is written once the delay elapses" do
      buffer = start_buffer(max_batch_size: 1_000, max_delay: to_timeout(millisecond: 50))

      Buffer.insert(buffer, log_line(1))

      assert_eventually(messages() == ["1"])
    end

    test "rows buffered during a flush are picked up by the next one" do
      buffer = start_buffer(max_batch_size: 5, max_delay: to_timeout(millisecond: 50))

      for n <- 1..12, do: Buffer.insert(buffer, log_line(n))

      assert_eventually(length(messages()) == 12)
    end
  end

  describe "overload" do
    test "drops the oldest rows once the buffer is full" do
      # Large enough triggers that only the size cap can fire.
      buffer =
        start_buffer(
          max_batch_size: 1_000_000,
          max_delay: to_timeout(minute: 1),
          max_buffer_size: 10
        )

      for n <- 1..15, do: Buffer.insert(buffer, log_line(n))

      :ok = Buffer.flush(buffer)

      # The 11th insert halves the buffer, dropping 1..5, and 11..15 refill it.
      written = messages()

      assert length(written) == 10
      refute "1" in written
      assert "6" in written
      assert "15" in written
    end
  end

  # Spans come to this process through the SDK's own span processor, which every
  # tracer already reports to. A flush runs in a task with no trace to join, so
  # there is no trace id to look for: these look at every flush of the table.
  describe "tracing" do
    setup do
      :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
      on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
    end

    test "a flush is a trace of its own, holding its insert as a ClickHouse query" do
      buffer = start_buffer(max_batch_size: 1_000, max_delay: to_timeout(minute: 1))

      Buffer.insert(buffer, log_line(1))
      :ok = Buffer.flush(buffer)

      spans = exported()
      flushes = for span(name: "Analytics.Buffer.flush[device_log_lines]") = flush <- spans, do: flush

      assert flushes != []

      for flush <- flushes do
        assert span(parent_span_id: :undefined, span_id: flush_span_id) = flush

        assert [span(name: "nerves_hub.analytics_repo.query", attributes: attributes)] =
                 for(span(parent_span_id: ^flush_span_id) = child <- spans, do: child)

        # The ClickHouse adapter gives an insert no source, so the span is named
        # without one, and the statement is what says which table it wrote.
        assert %{"db.system": :clickhouse, "db.statement": ~s(INSERT INTO "device_log_lines") <> _} =
                 :otel_attributes.map(attributes)
      end
    end
  end

  defp exported() do
    :otel_tracer_provider.force_flush()
    collect_exported([])
  end

  defp collect_exported(spans) do
    receive do
      {:span, span} -> collect_exported([span | spans])
    after
      200 -> spans
    end
  end

  defp start_buffer(opts) do
    name = :"buffer_test_#{System.unique_integer([:positive])}"

    start_supervised!({Buffer, [schema: LogLine, name: name] ++ opts})

    name
  end

  defp log_line(n) do
    LogLine.create_changeset(device_id(), @product_id, %{
      "timestamp" => DateTime.utc_now(),
      "level" => "info",
      "message" => to_string(n)
    })
  end

  # Scoped per test so a stray flush from another buffer cannot be read back here.
  defp device_id() do
    case Process.get(:buffer_test_device_id) do
      nil ->
        id = System.unique_integer([:positive])
        Process.put(:buffer_test_device_id, id)
        id

      id ->
        id
    end
  end

  defp messages() do
    LogLine
    |> where(device_id: ^device_id())
    |> select([l], l.message)
    |> AnalyticsRepo.all()
  end
end
