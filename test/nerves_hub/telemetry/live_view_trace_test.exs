defmodule NervesHub.Telemetry.LiveViewTraceTest do
  # The page load test swaps the exporter every test's spans go through.
  use NervesHubWeb.ConnCase.Browser, async: false

  alias NervesHub.Telemetry.LiveViewTrace
  alias Phoenix.LiveView.Socket

  require OpenTelemetry.Tracer, as: Tracer
  require Record

  Record.defrecordp(:span, Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl"))

  # An exporter that declines to start, which puts the span processor back the
  # way it starts when no exporter is configured: off, and holding nothing.
  defmodule NoExporter do
    @moduledoc false
    def init(_config), do: :ignore
  end

  describe "a page load" do
    setup do
      :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
      on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
    end

    # The connected mount runs in the LiveView's own process, which has no trace
    # but what the page's session carries. The dead render's mount runs in the
    # request, so it is the one whose parent isn't remote.
    test "the connected mount joins the request's trace, and later events don't", %{conn: conn} do
      {session, page} =
        Tracer.with_span "GET /account" do
          {visit(conn, "/account"), Tracer.current_span_ctx()}
        end

      click_button(session, "#change-password", "Change")

      spans = exported()
      page_trace_id = OpenTelemetry.Span.trace_id(page)
      page_span_id = OpenTelemetry.Span.span_id(page)

      for name <- ["NervesHubWeb.Live.Account.mount", "NervesHubWeb.Live.Account.handle_params"] do
        assert [span(trace_id: ^page_trace_id, parent_span_id: ^page_span_id)] =
                 for(span(name: ^name, parent_span_is_remote: true) = connected <- spans, do: connected)
      end

      assert [span(parent_span_id: :undefined, trace_id: event_trace_id)] =
               for(
                 span(name: "NervesHubWeb.Live.Account.handle_event#start-change-password") = event <- spans,
                 do: event
               )

      assert event_trace_id != page_trace_id
    end
  end

  describe "handle_mount/4" do
    setup do
      Tracer.with_span "GET /account" do
        %{
          session: LiveViewTrace.session(%Plug.Conn{}),
          trace_id: OpenTelemetry.Span.trace_id(Tracer.current_span_ctx())
        }
      end
    end

    test "holds the page's trace until the first render", %{session: session, trace_id: trace_id} do
      mount(connected(%{"_mounts" => 0}), session)
      assert OpenTelemetry.Span.trace_id(:otel_tracer.current_span_ctx()) == trace_id

      LiveViewTrace.handle_render([:phoenix, :live_view, :render, :stop], %{}, %{}, nil)
      assert :otel_tracer.current_span_ctx() == :undefined
    end

    test "leaves a reconnect, a live navigation, a nested LiveView and a dead render alone",
         %{session: session} do
      for socket <- [
            connected(%{"_mounts" => 1}),
            connected(%{"_mounts" => 0, "_live_referer" => "http://localhost/account"}),
            %{connected(%{"_mounts" => 0}) | parent_pid: self()},
            %Socket{}
          ] do
        mount(socket, session)
        assert :otel_tracer.current_span_ctx() == :undefined
      end
    end

    test "leaves a page with no trace alone" do
      assert LiveViewTrace.session(%Plug.Conn{}) == %{}

      mount(connected(%{"_mounts" => 0}), %{})
      assert :otel_tracer.current_span_ctx() == :undefined
    end
  end

  defp mount(socket, session) do
    LiveViewTrace.handle_mount([:phoenix, :live_view, :mount, :start], %{}, %{socket: socket, session: session}, nil)
  end

  defp connected(connect_params) do
    %Socket{transport_pid: self(), private: %{connect_params: connect_params}}
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
end
