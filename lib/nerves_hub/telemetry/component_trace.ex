defmodule NervesHub.Telemetry.ComponentTrace do
  @moduledoc """
  Runs a LiveComponent's `update` in a span, in the trace of the LiveView
  callback whose render called it.

  LiveView calls a component's `update` while rendering, after `mount`,
  `handle_params` or `handle_event` has returned. By then `opentelemetry_phoenix`
  has ended the callback's span and put back the context from before it, which
  in a connected LiveView holds no span. So the queries an `update` makes, and
  the async work it starts, would each start a trace of their own, sampled as
  `:default`, rather than join the page's. The deployment group Stats tab is
  one: it loads its numbers from `update`.

  `setup/0` attaches handlers that keep a callback's context as its span ends,
  hand it to the render that follows, and open a span under it around each
  component's `update`, named after the LiveView and the component:
  `NervesHubWeb.Live.DeploymentGroups.Show.update#NervesHubWeb.Components.DeploymentGroupPage.Stats`.
  The update's queries, and the spans of any `start_async` it calls
  (`NervesHub.Telemetry.AsyncTrace`), are children of that span. Like an async
  span, it usually ends after its parent, so Sentry sends it as a transaction of
  its own in the parent's trace.

  A callback's context is only kept when LiveView renders straight after it:
  the socket is connected, has changes to render, and isn't being redirected.
  The render takes it and drops it when it ends. A render after anything else,
  such as `handle_info` or `handle_async`, has no callback to join, so its
  components' updates get a span only if one is already current, as in the
  request that renders a page before it connects, and otherwise run as before.
  So no update span starts a trace, and no sampling rate changes.

  A component's own `handle_event` isn't kept either: LiveView renders the
  component alone after it, with no render event, and calls no `update` but
  its children's.

  The command palette's `update` never gets a span. It is in both layouts, so
  it updates on every page load, and it only sets assigns: a span for it would
  add a Sentry transaction to every page load and show nothing. Its search
  runs in an `assign_async` from its `handle_event`, which `AsyncTrace` traces.
  """

  alias NervesHubWeb.Components.CommandPalette
  alias Phoenix.LiveView.Socket

  require OpenTelemetry.Tracer, as: Tracer

  @callback_key {__MODULE__, :callback}
  @render_key {__MODULE__, :render}
  @updates_key {__MODULE__, :updates}

  # Components whose updates never get a span. See the moduledoc.
  @untraced [CommandPalette]

  @callback_stops [
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_event, :stop]
  ]

  @doc """
  Attaches the handlers.

  Call it before `OpentelemetryPhoenix.setup/1`. Telemetry runs handlers in the
  order they were attached, and a callback's span has to still be current when
  its context is kept.
  """
  @spec setup() :: :ok
  def setup() do
    :ok = :telemetry.attach_many({__MODULE__, :callback}, @callback_stops, &__MODULE__.handle_callback/4, nil)

    :ok =
      :telemetry.attach_many(
        {__MODULE__, :render},
        for(stage <- [:start, :stop, :exception], do: [:phoenix, :live_view, :render, stage]),
        &__MODULE__.handle_render/4,
        nil
      )

    :ok =
      :telemetry.attach_many(
        {__MODULE__, :update},
        for(stage <- [:start, :stop, :exception], do: [:phoenix, :live_component, :update, stage]),
        &__MODULE__.handle_update/4,
        nil
      )
  end

  @doc false
  def handle_callback(_event, _measurements, %{socket: %Socket{} = socket}, _config) do
    _ =
      if renders_next?(socket) and Tracer.current_span_ctx() != :undefined do
        Process.put(@callback_key, OpenTelemetry.Ctx.get_current())
      else
        Process.delete(@callback_key)
      end

    :ok
  end

  def handle_callback(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  def handle_render([:phoenix, :live_view, :render, :start], _measurements, _metadata, _config) do
    _ =
      case Process.delete(@callback_key) do
        nil -> Process.delete(@render_key)
        ctx -> Process.put(@render_key, ctx)
      end

    :ok
  end

  def handle_render(_stop_or_exception, _measurements, _metadata, _config) do
    _ = Process.delete(@render_key)
    :ok
  end

  @doc false
  def handle_update(
        [:phoenix, :live_component, :update, :start],
        _measurements,
        %{socket: %Socket{view: view}, component: component},
        _config
      ) do
    update =
      case parent(component) do
        nil ->
          nil

        parent ->
          span = Tracer.start_span(parent, "#{inspect(view)}.update##{inspect(component)}", %{kind: :internal})
          {span, OpenTelemetry.Ctx.attach(Tracer.set_current_span(parent, span))}
      end

    # Pushed even without a span, so each stop ends its own start's.
    Process.put(@updates_key, [update | Process.get(@updates_key, [])])
    :ok
  end

  def handle_update([:phoenix, :live_component, :update, stage], _measurements, metadata, _config)
      when stage in [:stop, :exception] do
    case Process.get(@updates_key, []) do
      [update | updates] ->
        Process.put(@updates_key, updates)
        finish(update, metadata)

      [] ->
        :ok
    end
  end

  def handle_update(_event, _measurements, _metadata, _config), do: :ok

  # The same test LiveView makes before it renders: it renders a socket with
  # changes, unless it's being sent elsewhere. A connected one only, as the
  # render before a page connects sends no render event to drop the context.
  defp renders_next?(%Socket{transport_pid: transport_pid, redirected: nil, assigns: %{__changed__: changed}})
       when is_pid(transport_pid), do: changed != %{}

  defp renders_next?(_socket), do: false

  defp parent(component) when component in @untraced, do: nil

  defp parent(_component) do
    case Process.get(@render_key) do
      nil -> if Tracer.current_span_ctx() != :undefined, do: OpenTelemetry.Ctx.get_current()
      ctx -> ctx
    end
  end

  defp finish(nil, _metadata), do: :ok

  defp finish({span, token}, metadata) do
    _ =
      case metadata do
        %{kind: kind, reason: reason, stacktrace: stacktrace} ->
          OpenTelemetry.Span.set_status(
            span,
            OpenTelemetry.status(:error, Exception.format_banner(kind, reason, stacktrace))
          )

        _stop ->
          :ok
      end

    _ = OpenTelemetry.Span.end_span(span)
    _ = OpenTelemetry.Ctx.detach(token)
    :ok
  end
end
