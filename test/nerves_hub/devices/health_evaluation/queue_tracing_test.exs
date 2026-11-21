defmodule NervesHub.Devices.HealthEvaluation.QueueTracingTest do
  @moduledoc """
  The trace a health evaluation runs in.

  Kept apart from `NervesHub.Devices.HealthEvaluation.QueueTest`, which runs
  async: these swap the span exporter, which every test shares.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.Devices.HealthEvaluation.Queue
  alias NervesHub.Repo

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))
  Record.defrecordp(:link, Record.extract(:link, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  setup do
    # The SDK's own span processor, which every tracer already reports to.
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)

    test = self()

    # Makes a query, as a real evaluation does, and says which span it ran in.
    evaluator = fn _device_info, _samples ->
      _ = Repo.query!("SELECT 1")
      send(test, {:evaluated_in, Tracer.current_span_ctx()})
      :ok
    end

    name = :"health_evaluation_queue_#{System.unique_integer([:positive])}"
    tasks = :"#{name}_tasks"

    start_supervised!({Task.Supervisor, name: tasks}, id: tasks)
    start_supervised!({Queue, name: name, evaluator: evaluator, task_supervisor: tasks}, id: name)

    %{queue: name}
  end

  test "an evaluation is a trace of its own, linked to the report that queued it", %{queue: queue} do
    report =
      Tracer.with_span "Channels.ExtensionsChannel.handle_in" do
        :ok = Queue.enqueue(queue, device_info(), [])
        Tracer.current_span_ctx()
      end

    evaluation = evaluated(queue)

    refute OpenTelemetry.Span.trace_id(evaluation) == OpenTelemetry.Span.trace_id(report)

    report_trace_id = OpenTelemetry.Span.trace_id(report)
    report_span_id = OpenTelemetry.Span.span_id(report)

    assert {[span(name: "Devices.HealthEvaluation.Queue.evaluate", parent_span_id: :undefined, links: links)], _rest} =
             exported_trace(evaluation)

    assert [link(trace_id: ^report_trace_id, span_id: ^report_span_id)] = :otel_links.list(links)
  end

  test "the queries an evaluation makes are in its trace", %{queue: queue} do
    :ok = Queue.enqueue(queue, device_info(), [])

    evaluation = evaluated(queue)
    evaluation_span_id = OpenTelemetry.Span.span_id(evaluation)

    assert {[_evaluation], [span(name: "nerves_hub.repo.query", parent_span_id: ^evaluation_span_id)]} =
             exported_trace(evaluation)
  end

  test "a report made outside any trace is evaluated without a link", %{queue: queue} do
    :ok = Queue.enqueue(queue, device_info(), [])

    assert {[span(links: links)], _rest} = queue |> evaluated() |> exported_trace()
    assert :otel_links.list(links) == []
  end

  defp device_info(), do: %DeviceInfo{device_id: 1, device_identifier: "device-1", connection_ref: "first"}

  # The span the evaluation ran in, once it has finished, and its span with it.
  defp evaluated(queue) do
    :ok = Queue.drain(server: queue)
    assert_receive {:evaluated_in, span_ctx}
    span_ctx
  end

  # The evaluation's exported span, and the rest of its trace. Other tests'
  # spans arrive too, so only this trace's are kept.
  defp exported_trace(span_ctx) do
    span_id = OpenTelemetry.Span.span_id(span_ctx)
    trace_id = OpenTelemetry.Span.trace_id(span_ctx)

    :otel_tracer_provider.force_flush()

    trace_id
    |> collect_exported([])
    |> Enum.split_with(&(span(&1, :span_id) == span_id))
  end

  defp collect_exported(trace_id, spans) do
    receive do
      {:span, span(trace_id: ^trace_id) = span} -> collect_exported(trace_id, [span | spans])
    after
      200 -> Enum.reverse(spans)
    end
  end
end
