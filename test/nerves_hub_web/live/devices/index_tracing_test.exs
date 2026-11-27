defmodule NervesHubWeb.Live.Devices.IndexTracingTest do
  @moduledoc """
  The trace the devices list's async loads run in.

  Kept apart from `NervesHubWeb.Live.Devices.IndexTest`: these swap the span
  exporter, which every test shares.
  """

  use NervesHubWeb.ConnCase.Browser, async: false

  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  setup do
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
  end

  test "the list's queries are in the trace of the handle_params that asked for it", %{
    conn: conn,
    fixture: %{device: device, org: org, product: product}
  } do
    {:ok, lv, _html} = live(conn, ~p"/org/#{org}/#{product}/devices")
    assert render_async(lv, 5_000) =~ device.identifier

    spans = exported()

    assert [span(trace_id: trace_id, span_id: list_id, parent_span_id: parent_id)] =
             named(spans, "NervesHubWeb.Live.Devices.Index.start_async#update_device_list")

    # The connected mount's, the one that starts the task.
    assert [span(trace_id: ^trace_id)] =
             for(
               span(name: "NervesHubWeb.Live.Devices.Index.handle_params", span_id: ^parent_id) = span <- spans,
               do: span
             )

    # `Devices.filter/3`, `Devices.state_counts/3` and `Devices.count_by_product/2`
    assert [_ | _] = queries = named(spans, "nerves_hub.repo.query:devices", list_id)
    assert Enum.uniq(for span(trace_id: query_trace_id) <- queries, do: query_trace_id) == [trace_id]
  end

  defp named(spans, name), do: for(span(name: ^name) = span <- spans, do: span)

  defp named(spans, name, parent_id), do: for(span(name: ^name, parent_span_id: ^parent_id) = span <- spans, do: span)

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
end
