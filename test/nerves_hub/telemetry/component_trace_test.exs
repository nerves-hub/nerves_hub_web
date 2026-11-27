defmodule NervesHub.Telemetry.ComponentTraceTest do
  # Not async: it swaps the exporter every test's spans go through.
  use ExUnit.Case, async: false

  alias NervesHub.Telemetry.ComponentTrace
  alias NervesHubWeb.Components.CommandPalette
  alias NervesHubWeb.Components.DeploymentGroupPage.Stats
  alias NervesHubWeb.Live.DeploymentGroups.Show
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

  @update_span "NervesHubWeb.Live.DeploymentGroups.Show.update#NervesHubWeb.Components.DeploymentGroupPage.Stats"

  setup do
    :ok = :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    on_exit(fn -> :ok = :otel_batch_processor.set_exporter(NoExporter, []) end)
  end

  # As in LiveView: the callback's span ends, and its context is put back,
  # before the render that calls the component's update starts.
  test "an update in the render after a callback runs in a span under the callback's" do
    callback =
      Tracer.with_span "NervesHubWeb.Live.DeploymentGroups.Show.handle_params" do
        callback_stop(socket())
        Tracer.current_span_ctx()
      end

    update = render(fn -> update(&Tracer.current_span_ctx/0) end)

    assert Tracer.current_span_ctx() == :undefined

    callback_id = OpenTelemetry.Span.span_id(callback)
    update_id = OpenTelemetry.Span.span_id(update)

    assert [span(span_id: ^update_id, parent_span_id: ^callback_id)] =
             callback |> OpenTelemetry.Span.trace_id() |> exported() |> named(@update_span)
  end

  test "an update in a render that doesn't follow a callback runs without a span" do
    for socket <- [
          # Nothing to render, so the next render follows something else.
          socket(%{}),
          # Sent elsewhere, so LiveView doesn't render.
          %{socket() | redirected: {:live, :patch, %{to: "/", kind: :push}}},
          # The render before a page connects sends no render event.
          %{socket() | transport_pid: nil}
        ] do
      Tracer.with_span "NervesHubWeb.Live.DeploymentGroups.Show.handle_event#save" do
        callback_stop(socket)
      end

      assert render(fn -> update(&Tracer.current_span_ctx/0) end) == :undefined
    end
  end

  # It's in both layouts, so it updates on every page load, and only sets
  # assigns.
  test "the command palette's update runs without a span" do
    Tracer.with_span "NervesHubWeb.Live.DeploymentGroups.Show.handle_params" do
      callback_stop(socket())
    end

    palette = %{component: CommandPalette}

    assert render(fn ->
             handle_update(:start, palette)
             current = Tracer.current_span_ctx()
             handle_update(:stop, palette)
             current
           end) == :undefined
  end

  test "a render drops the callback's context when it ends" do
    Tracer.with_span "NervesHubWeb.Live.DeploymentGroups.Show.handle_event#save" do
      callback_stop(socket())
    end

    render(fn -> :ok end)

    # A `send_update`, outside any render, and the render after a `handle_info`.
    assert update(&Tracer.current_span_ctx/0) == :undefined
    assert render(fn -> update(&Tracer.current_span_ctx/0) end) == :undefined
  end

  # The render in the request that renders a page before it connects.
  test "an update outside a render runs in a span under the one current" do
    {request, update} =
      Tracer.with_span "GET /org/:org_name/:product_name/deployment_groups/:name/stats" do
        {Tracer.current_span_ctx(), update(&Tracer.current_span_ctx/0)}
      end

    request_id = OpenTelemetry.Span.span_id(request)
    update_id = OpenTelemetry.Span.span_id(update)

    assert [span(span_id: ^update_id, parent_span_id: ^request_id)] =
             request |> OpenTelemetry.Span.trace_id() |> exported() |> named(@update_span)
  end

  test "an update that raises ends its span, marked as failed, and puts the context back" do
    Tracer.with_span "NervesHubWeb.Live.DeploymentGroups.Show.handle_params" do
      callback_stop(socket())
    end

    update =
      render(fn ->
        handle_update(:start, %{})
        update = Tracer.current_span_ctx()

        handle_update(:exception, %{kind: :error, reason: %RuntimeError{message: "boom"}, stacktrace: []})
        assert Tracer.current_span_ctx() == :undefined

        update
      end)

    assert [span(status: status)] =
             update |> OpenTelemetry.Span.trace_id() |> exported() |> named(@update_span)

    assert status == OpenTelemetry.status(:error, "** (RuntimeError) boom")
  end

  defp socket(changed \\ %{selection: true}) do
    %Socket{view: Show, transport_pid: self(), assigns: %{__changed__: changed}}
  end

  # Called while the callback's span is still current, as its handler runs
  # before `opentelemetry_phoenix`'s.
  defp callback_stop(socket) do
    ComponentTrace.handle_callback([:phoenix, :live_view, :handle_event, :stop], %{}, %{socket: socket}, nil)
  end

  defp render(fun) do
    ComponentTrace.handle_render([:phoenix, :live_view, :render, :start], %{}, %{}, nil)
    result = fun.()
    ComponentTrace.handle_render([:phoenix, :live_view, :render, :stop], %{}, %{}, nil)
    result
  end

  defp update(fun) do
    handle_update(:start, %{})
    result = fun.()
    handle_update(:stop, %{})
    result
  end

  defp handle_update(stage, metadata) do
    ComponentTrace.handle_update(
      [:phoenix, :live_component, :update, stage],
      %{},
      Map.merge(%{socket: socket(), component: Stats}, metadata),
      nil
    )
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
