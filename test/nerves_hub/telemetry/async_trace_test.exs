defmodule NervesHub.Telemetry.AsyncTraceTest do
  # Not async: it swaps the exporter every test's spans go through.
  use NervesHub.DataCase, async: false

  alias NervesHub.Repo
  alias NervesHub.Telemetry.AsyncTrace
  alias NervesHubWeb.Live.Devices.Index
  alias Phoenix.LiveView.Socket

  require AsyncTrace
  require OpenTelemetry.Tracer, as: Tracer
  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  @socket %Socket{view: Index}

  setup do
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
  end

  describe "run/2" do
    # As in a LiveView: the callback's span has ended, and its process has
    # moved on, before the task makes its first query.
    test "runs the work under the caller's span, and its queries under it, after the caller's span has ended" do
      {caller, trace} =
        Tracer.with_span "NervesHubWeb.Live.Devices.Index.handle_params" do
          {Tracer.current_span_ctx(), AsyncTrace.trace(@socket, :start_async, :update_device_list)}
        end

      task =
        Task.async(fn ->
          AsyncTrace.run(trace, fn ->
            Repo.query!("SELECT 1")
            Tracer.current_span_ctx()
          end)
        end)

      work = Task.await(task)

      trace_id = OpenTelemetry.Span.trace_id(caller)
      caller_id = OpenTelemetry.Span.span_id(caller)
      work_id = OpenTelemetry.Span.span_id(work)

      assert OpenTelemetry.Span.trace_id(work) == trace_id

      spans = exported(trace_id)

      assert [span(span_id: ^work_id, parent_span_id: ^caller_id)] =
               named(spans, "NervesHubWeb.Live.Devices.Index.start_async#update_device_list")

      assert [span(parent_span_id: ^work_id)] = named(spans, "nerves_hub.repo.query")
    end

    test "starts a trace of its own where no span is current" do
      work = AsyncTrace.run(AsyncTrace.trace(@socket, :start_async, :load_peek), &Tracer.current_span_ctx/0)

      assert [span(parent_span_id: :undefined)] =
               work
               |> OpenTelemetry.Span.trace_id()
               |> exported()
               |> named("NervesHubWeb.Live.Devices.Index.start_async#load_peek")
    end

    test "ends the span, marked as failed, and puts the context back when the work raises" do
      Tracer.with_span "caller" do
        caller = Tracer.current_span_ctx()
        trace = AsyncTrace.trace(@socket, :start_async, :load_facets)

        assert_raise RuntimeError, "boom", fn -> AsyncTrace.run(trace, fn -> raise "boom" end) end
        assert Tracer.current_span_ctx() == caller

        assert [span(status: status)] =
                 caller |> OpenTelemetry.Span.trace_id() |> exported() |> named(elem(trace, 1))

        assert status == OpenTelemetry.status(:error, "** (RuntimeError) boom")
      end
    end

    test "ends the span, marked as failed, and puts the context back when the work exits" do
      Tracer.with_span "caller" do
        caller = Tracer.current_span_ctx()
        trace = AsyncTrace.trace(@socket, :start_async, :load_facets)

        assert catch_exit(AsyncTrace.run(trace, fn -> exit(:timeout) end)) == :timeout
        assert Tracer.current_span_ctx() == caller

        assert [span(status: status)] =
                 caller |> OpenTelemetry.Span.trace_id() |> exported() |> named(elem(trace, 1))

        assert status == OpenTelemetry.status(:error, "** (exit) time out")
      end
    end
  end

  describe "start_async/4 and assign_async/4" do
    test "run the task's work under the caller's span" do
      caller =
        Tracer.with_span "NervesHubWeb.Live.Devices.Index.handle_event#search" do
          # Connected, so the tasks start, and their results come back here.
          %Socket{view: Index, transport_pid: self()}
          |> AsyncTrace.start_async(:load_peek, &Tracer.current_span_ctx/0)
          |> AsyncTrace.assign_async(:peek, fn -> {:ok, %{peek: Tracer.current_span_ctx()}} end)

          Tracer.current_span_ctx()
        end

      # Each arrives once its span has ended.
      assert_receive {:phoenix, :async_result, {:start, {_ref, _cid, :load_peek, {:ok, started}}}}
      assert_receive {:phoenix, :async_result, {:assign, {_ref, _cid, [:peek], {:ok, {:ok, %{peek: assigned}}}}}}

      caller_id = OpenTelemetry.Span.span_id(caller)
      started_id = OpenTelemetry.Span.span_id(started)
      assigned_id = OpenTelemetry.Span.span_id(assigned)
      spans = caller |> OpenTelemetry.Span.trace_id() |> exported()

      assert [span(span_id: ^started_id, parent_span_id: ^caller_id)] =
               named(spans, "NervesHubWeb.Live.Devices.Index.start_async#load_peek")

      assert [span(span_id: ^assigned_id, parent_span_id: ^caller_id)] =
               named(spans, "NervesHubWeb.Live.Devices.Index.assign_async#peek")
    end
  end

  describe "trace/3" do
    test "names the span after the view and what the async is, not which one" do
      for {op, name, span_name} <- [
            {:start_async, :update_device_list, "NervesHubWeb.Live.Devices.Index.start_async#update_device_list"},
            {:start_async, {:send_test, 12}, "NervesHubWeb.Live.Devices.Index.start_async#send_test"},
            {:start_async, "load_chart:cpu_temp", "NervesHubWeb.Live.Devices.Index.start_async#load_chart"},
            {:start_async, "update_chart:a:b", "NervesHubWeb.Live.Devices.Index.start_async#update_chart"},
            {:start_async, "load_offline", "NervesHubWeb.Live.Devices.Index.start_async#load_offline"},
            {:assign_async, :failed_installs, "NervesHubWeb.Live.Devices.Index.assign_async#failed_installs"},
            {:assign_async, [:profile, :rank], "NervesHubWeb.Live.Devices.Index.assign_async#profile,rank"}
          ] do
        assert {_ctx, ^span_name} = AsyncTrace.trace(@socket, op, name)
        assert AsyncTrace.span?(span_name)
      end
    end
  end

  describe "span?/1" do
    test "is false for a LiveView's own spans" do
      refute AsyncTrace.span?("NervesHubWeb.Live.Devices.Index.handle_event#search")
      refute AsyncTrace.span?("NervesHubWeb.Live.Devices.Index.handle_params")
      refute AsyncTrace.span?(:undefined)
    end
  end

  defp named(spans, name), do: for(span(name: ^name) = span <- spans, do: span)

  # Other tests' spans arrive too, so only this trace's are kept.
  defp exported(trace_id) do
    :otel_tracer_provider.force_flush()
    collect_exported(trace_id, [])
  end

  defp collect_exported(trace_id, spans) do
    receive do
      {:span, span(trace_id: ^trace_id) = span} -> collect_exported(trace_id, [span | spans])
    after
      200 -> Enum.reverse(spans)
    end
  end
end
