defmodule NervesHub.Debug do
  @moduledoc """
  Tools for debugging performance in production.
  """

  def mark(label) do
    t = Process.get(:t)
    s = Process.get(:s)

    new_t =
      if t do
        new = System.monotonic_time(:millisecond)
        IO.puts("#{label} [#{inspect(self())}]: #{new - t} | #{new - s} ms")
        new
      else
        IO.puts("#{label} new process")
        v = System.monotonic_time(:millisecond)
        Process.put(:s, v)
        v
      end

    Process.put(:t, new_t)
  end

  def mark(piped, label) do
    mark(label)
    piped
  end

  def log_slow_queries(threshold_ms \\ 100) do
    pid = self()
    _ = :telemetry.detach("ecto-debug-handler")

    :ok =
      :telemetry.attach(
        "ecto-debug-handler",
        [:nerves_hub, :repo, :query],
        fn event, measurements, metadata, config ->
          send(pid, {:event, event, measurements, metadata, config})
        end,
        %{}
      )

    spawn(fn ->
      :timer.sleep(30_000)
      _ = :telemetry.detach("ecto-debug-handler")
      send(pid, :done)
    end)

    wait_for_query(threshold_ms)

    :ok
  end

  defp wait_for_query(threshold_ms) do
    threshold = System.convert_time_unit(threshold_ms, :millisecond, :native)

    receive do
      {:event, event, measurements, metadata, _config} ->
        measurements = Map.delete(measurements, :idle_time)

        if Enum.any?(measurements, fn {_k, v} -> v > threshold end) do
          IO.inspect(metadata)

          Enum.each(measurements, fn {k, v} ->
            if v > threshold do
              ms = System.convert_time_unit(v, :native, :millisecond)
              IO.inspect("#{inspect(event)} #{k}: #{ms} milliseconds")
            end
          end)
        end

        wait_for_query(threshold_ms)

      :done ->
        :ok
    after
      30_000 ->
        :timeout
    end
  end

  def time_function({_, _, _} = recon_pattern, samples, sample_timeout \\ 10_000) do
    pid = self()

    :recon_trace.calls(recon_pattern, samples,
      timestamp: :trace,
      formatter: fn term ->
        send(pid, {:sample, term})
        "Collected trace.\n"
      end
    )

    wait_samples(samples, samples, sample_timeout)
  end

  defp wait_samples(0, _limit, _timeout) do
    :ok
  end

  defp wait_samples(count, limit, timeout) do
    receive do
      {:sample, {:trace_ts, _pid, :call, {_m, _f, _args}, erlang_ts}} ->
        microseconds = ts_to_micro(erlang_ts)
        IO.puts("Sample call start, #{microseconds}uS")
        wait_samples(count - 1, limit, timeout)

      {:sample, term} ->
        IO.inspect(term, label: "sample", limit: :infinity)
        wait_samples(count - 1, limit, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp ts_to_micro({megaseconds, seconds, microseconds}) do
    microseconds
    |> add(seconds_to_micro(seconds))
    |> add(megaseconds_to_micro(megaseconds))
  end

  defp add(a, b), do: a + b
  defp seconds_to_micro(seconds), do: seconds * 1_000_000
  defp megaseconds_to_micro(megaseconds), do: megaseconds * 1_000_000_000_000
end
