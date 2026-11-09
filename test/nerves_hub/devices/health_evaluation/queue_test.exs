defmodule NervesHub.Devices.HealthEvaluation.QueueTest do
  @moduledoc """
  The queue between a device's report and its health evaluation.

  Each test runs its own queue, with an evaluator that tells the test what it
  was given and then waits to be let go. That makes "how many are running" and
  "what got judged" things a test can see and decide, rather than race.
  """

  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.HealthEvaluation.Queue

  @dropped [:nerves_hub, :health_evaluation, :dropped]
  @evaluated [:nerves_hub, :health_evaluation, :evaluated]

  setup do
    test = self()
    handler = "queue-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler,
        [@dropped, @evaluated],
        fn event, measurements, metadata, _config -> send(test, {:telemetry, event, measurements, metadata}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    :ok
  end

  # An evaluator that reports what it was handed, then waits for `release/1`.
  defp blocking_evaluator(test \\ self()) do
    fn device_info, samples ->
      send(test, {:evaluating, self(), device_info, samples})

      receive do
        {:release, result} -> result
      end
    end
  end

  # With a task supervisor of its own, so evaluations a test leaves blocked
  # stop with it.
  defp start_queue(opts) do
    name = :"health_evaluation_queue_#{System.unique_integer([:positive])}"
    tasks = :"#{name}_tasks"

    start_supervised!({Task.Supervisor, name: tasks}, id: tasks)

    opts = Keyword.merge([name: name, evaluator: blocking_evaluator(), concurrency: 1, task_supervisor: tasks], opts)

    start_supervised!({Queue, opts}, id: name)

    name
  end

  defp device_info(device_id, connection_ref \\ "first") do
    %DeviceInfo{device_id: device_id, device_identifier: "device-#{device_id}", connection_ref: connection_ref}
  end

  defp device_id(), do: System.unique_integer([:positive])

  defp reading(key, seconds_ago, value) do
    {key, DateTime.add(~U[2026-11-08 12:00:00.000000Z], -seconds_ago, :second), value}
  end

  defp release(pid, result \\ :ok), do: send(pid, {:release, result})

  describe "a report" do
    test "is evaluated with the device and readings it brought" do
      queue = start_queue([])
      id = device_id()
      samples = [reading("cpu", 0, 40.0)]

      :ok = Queue.enqueue(queue, device_info(id), samples)

      assert_receive {:evaluating, pid, %DeviceInfo{device_id: ^id}, ^samples}
      release(pid)

      :ok = Queue.drain(server: queue)
      assert_received {:telemetry, @evaluated, %{wait_time: _, duration: _}, %{device_id: ^id, result: :ok}}
    end

    test "is evaluated on behalf of whoever queued it" do
      test = self()

      queue =
        start_queue(
          evaluator: fn _device_info, _samples ->
            send(test, {:callers, Process.get(:"$callers")})
            :ok
          end
        )

      :ok = Queue.enqueue(queue, device_info(device_id()), [])

      # Which is what lets the Ecto sandbox find a test's connection.
      assert_receive {:callers, [^test | _]}
    end
  end

  describe "a device that reports again before it is evaluated" do
    setup do
      queue = start_queue(concurrency: 1)

      # Hold the only worker, so what comes next has to wait in line.
      busy = device_id()
      :ok = Queue.enqueue(queue, device_info(busy), [])
      assert_receive {:evaluating, worker, %DeviceInfo{device_id: ^busy}, _samples}

      %{queue: queue, worker: worker}
    end

    test "is judged once, as its newest report describes it, with every reading", %{queue: queue, worker: worker} do
      id = device_id()

      :ok = Queue.enqueue(queue, device_info(id, "first"), [reading("cpu", 60, 90.0)])
      :ok = Queue.enqueue(queue, device_info(id, "second"), [reading("cpu", 0, 20.0), reading("mem", 0, 50.0)])

      release(worker)

      assert_receive {:evaluating, pid, %DeviceInfo{device_id: ^id, connection_ref: "second"}, samples}

      # The first report's reading may still be in the write buffer, so it
      # comes along rather than being replaced.
      assert Enum.sort(samples) ==
               Enum.sort([reading("cpu", 60, 90.0), reading("cpu", 0, 20.0), reading("mem", 0, 50.0)])

      release(pid)
      :ok = Queue.drain(server: queue)

      refute_received {:evaluating, _pid, %DeviceInfo{device_id: ^id}, _samples}
    end

    test "counts a reading delivered twice once", %{queue: queue, worker: worker} do
      id = device_id()

      :ok = Queue.enqueue(queue, device_info(id), [reading("cpu", 0, 20.0)])
      :ok = Queue.enqueue(queue, device_info(id), [reading("cpu", 0, 20.0)])

      release(worker)

      assert_receive {:evaluating, _pid, %DeviceInfo{device_id: ^id}, [{"cpu", _at, 20.0}]}
    end

    test "keeps the newest readings, up to a limit", %{queue: queue, worker: worker} do
      id = device_id()

      :ok = Queue.enqueue(queue, device_info(id), for(s <- 1_000..1_999, do: reading("cpu", s, 1.0)))
      :ok = Queue.enqueue(queue, device_info(id), for(s <- 0..999, do: reading("cpu", s, 2.0)))

      release(worker)

      assert_receive {:evaluating, _pid, %DeviceInfo{device_id: ^id}, samples}
      assert length(samples) == 1_200

      # Everything from the newer report, and the newest of the older one.
      oldest_kept = samples |> Enum.map(fn {_key, at, _value} -> at end) |> Enum.min(DateTime)
      assert oldest_kept == elem(reading("cpu", 1_199, 1.0), 1)
    end

    test "keeps its place in line", %{queue: queue, worker: worker} do
      first = device_id()
      second = device_id()

      :ok = Queue.enqueue(queue, device_info(first), [])
      :ok = Queue.enqueue(queue, device_info(second), [])
      :ok = Queue.enqueue(queue, device_info(first), [])

      release(worker)

      assert_receive {:evaluating, pid, %DeviceInfo{device_id: ^first}, _samples}
      release(pid)

      assert_receive {:evaluating, _pid, %DeviceInfo{device_id: ^second}, _samples}
    end
  end

  describe "concurrency" do
    test "never runs more than the limit at once" do
      queue = start_queue(concurrency: 2)
      ids = for _ <- 1..4, do: device_id()

      Enum.each(ids, &Queue.enqueue(queue, device_info(&1), []))

      assert_receive {:evaluating, first, _, _samples}
      assert_receive {:evaluating, _second, _, _samples}
      refute_receive {:evaluating, _pid, _, _samples}, 50

      release(first)

      assert_receive {:evaluating, _third, _, _samples}
      refute_receive {:evaluating, _pid, _, _samples}, 50
    end

    test "judges a device once at a time, even with workers free" do
      queue = start_queue(concurrency: 2)
      id = device_id()

      :ok = Queue.enqueue(queue, device_info(id, "first"), [])
      assert_receive {:evaluating, pid, %DeviceInfo{connection_ref: "first"}, _samples}

      # A report while it is being judged. A second worker is free, but using
      # it could save the older verdict last.
      :ok = Queue.enqueue(queue, device_info(id, "second"), [])
      refute_receive {:evaluating, _pid, _, _samples}, 50

      release(pid)

      assert_receive {:evaluating, _pid, %DeviceInfo{device_id: ^id, connection_ref: "second"}, _samples}
    end

    test "defaults to half the analytics pool, and at most 10" do
      queue = start_queue(concurrency: nil) |> GenServer.whereis()

      # Ecto's default pool, in this environment.
      assert %{concurrency: 5} = :sys.get_state(queue)
    end
  end

  describe "an evaluation that waited too long" do
    test "is dropped, counted and summarised, and not reported" do
      test = self()

      queue =
        start_queue(
          max_age: 0,
          summary_interval: 50,
          reporter: fn _device_info, error, _extra -> send(test, {:reported, error}) end
        )

      id = device_id()

      log =
        capture_log(fn ->
          :ok = Queue.enqueue(queue, device_info(id), [reading("cpu", 0, 95.0)])
          :ok = Queue.drain(server: queue)

          assert_received {:telemetry, @dropped, %{count: 1, wait_time: _}, %{device_id: ^id}}
          refute_received {:evaluating, _pid, _, _samples}

          Process.sleep(100)
        end)

      assert log =~ "1 dropped after waiting over 0s, 0 failed"
      refute_received {:reported, _error}
    end
  end

  describe "an evaluation that fails" do
    setup do
      test = self()

      queue =
        start_queue(
          concurrency: 1,
          summary_interval: 60_000,
          evaluator: fn device_info, _samples ->
            send(test, {:evaluating, self(), device_info, []})
            raise "ClickHouse is having a bad day"
          end,
          reporter: fn device_info, error, _extra -> send(test, {:reported, device_info.device_id, error}) end
        )

      %{queue: queue}
    end

    test "is counted, and the queue carries on", %{queue: queue} do
      first = device_id()
      second = device_id()

      capture_log(fn ->
        :ok = Queue.enqueue(queue, device_info(first), [])
        :ok = Queue.enqueue(queue, device_info(second), [])
        :ok = Queue.drain(server: queue)
      end)

      assert_received {:telemetry, @evaluated, _measurements, %{device_id: ^first, result: :failed}}
      assert_received {:telemetry, @evaluated, _measurements, %{device_id: ^second, result: :failed}}
    end

    test "is reported once per interval, however many there are", %{queue: queue} do
      first = device_id()
      second = device_id()

      capture_log(fn ->
        :ok = Queue.enqueue(queue, device_info(first), [])
        :ok = Queue.enqueue(queue, device_info(second), [])
        :ok = Queue.drain(server: queue)
      end)

      assert_receive {:reported, ^first, %RuntimeError{message: "ClickHouse is having a bad day"}}
      refute_receive {:reported, ^second, _error}, 50
    end
  end

  describe "drain/1" do
    test "can wait for one device alone" do
      queue = start_queue(concurrency: 2)
      waiting_on = device_id()
      other = device_id()

      :ok = Queue.enqueue(queue, device_info(other), [])
      :ok = Queue.enqueue(queue, device_info(waiting_on), [])

      assert_receive {:evaluating, _other, %DeviceInfo{device_id: ^other}, _samples}
      assert_receive {:evaluating, pid, %DeviceInfo{device_id: ^waiting_on}, _samples}

      release(pid)

      # The other device is still being judged, and that does not hold this up.
      assert :ok = Queue.drain(server: queue, device_id: waiting_on, timeout: 500)
    end
  end
end
