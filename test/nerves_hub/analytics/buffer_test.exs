defmodule NervesHub.Analytics.BufferTest do
  # Not async: these tests interact with the AnalyticsRepo, which is a ClickHouse
  # database that does not support concurrent writes.
  use NervesHub.DataCase, async: false
  use AssertEventually, timeout: 2000, interval: 50

  alias NervesHub.Analytics.Buffer
  alias NervesHub.AnalyticsRepo
  alias NervesHub.Devices.LogLine

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
