defmodule NervesHub.Telemetry.LiveViewTrace do
  @moduledoc """
  Puts a page's connected LiveView mount in the trace of the request that
  rendered the page, so one page load is one trace.

  A LiveView mounts twice: once in the request that renders the page, and again
  in a process of its own once the browser connects. That process starts with
  no trace, so its mount and `handle_params` would each start a new one.
  `session/1` puts the request's trace in the LiveView's session, which the page
  carries to the connected mount, and the handlers `setup/0` attaches continue
  it there. The connected mount's spans then follow the request's sampling
  decision.

  Only the page load joins the request's trace: the connected mount of a page
  the browser has just loaded, and its `handle_params`. The trace is let go
  after the first render, so the events, timers and refreshes that follow start
  traces of their own, as before. A reconnect (`"_mounts"` above 0) or a live
  navigation (`"_live_referer"` set) starts its own trace too, because the
  session it mounts with is from an earlier page. So does a nested LiveView.

  `Sentry.OpenTelemetry.LiveViewPropagator` does much the same from the session
  cookie, but it holds on to the request's trace for the whole life of the
  LiveView, and of every LiveView navigated to over the same socket.
  """

  alias Phoenix.LiveView.Socket

  @session_key "trace_context"
  @token_key {__MODULE__, :token}

  @doc """
  The request's trace, for the `:session` of a `live_session`.

  Empty when the request has no trace, so a page that isn't traced carries
  nothing extra.
  """
  @spec session(Plug.Conn.t()) :: %{optional(String.t()) => [{String.t(), String.t()}]}
  def session(_conn) do
    case :otel_propagator_text_map.inject([]) do
      [] -> %{}
      carrier -> %{@session_key => carrier}
    end
  end

  @doc """
  Attaches the handlers that continue a page's trace in its connected mount.

  Call it before `OpentelemetryPhoenix.setup/1`. Telemetry runs handlers in the
  order they were attached, and the trace has to be in place before
  `opentelemetry_phoenix` opens the mount's span.
  """
  @spec setup() :: :ok
  def setup() do
    :ok =
      :telemetry.attach(
        {__MODULE__, :mount},
        [:phoenix, :live_view, :mount, :start],
        &__MODULE__.handle_mount/4,
        nil
      )

    :ok =
      :telemetry.attach(
        {__MODULE__, :render},
        [:phoenix, :live_view, :render, :stop],
        &__MODULE__.handle_render/4,
        nil
      )
  end

  @doc false
  def handle_mount(_event, _measurements, %{socket: socket} = metadata, _config) do
    _ =
      with true <- page_load?(socket),
           [_ | _] = carrier <- get_in(metadata, [:session, @session_key]),
           :undefined <- :otel_tracer.current_span_ctx() do
        ctx = :otel_propagator_text_map.extract_to(:otel_ctx.get_current(), carrier)

        # Wrapped, because the token is the context from before, which in a new
        # process is `:undefined`, and `Process.delete/1` returns that as `nil`.
        Process.put(@token_key, {:attached, :otel_ctx.attach(ctx)})
      end

    :ok
  end

  # `opentelemetry_phoenix` puts back the context it found when a span ends, so
  # without this every later span in the LiveView would join the page's trace.
  # It doesn't handle render events, so the order of the handlers doesn't
  # matter here.
  @doc false
  def handle_render(_event, _measurements, _metadata, _config) do
    _ =
      case Process.delete(@token_key) do
        {:attached, token} -> :otel_ctx.detach(token)
        nil -> :ok
      end

    :ok
  end

  # The connected mount of a page the browser has just loaded. This reads what
  # `Phoenix.LiveView.get_connect_params/1` would, without its raise for a
  # nested LiveView, since a handler that raises is detached for good.
  defp page_load?(%Socket{
         transport_pid: transport_pid,
         parent_pid: nil,
         private: %{connect_params: %{"_mounts" => 0} = connect_params}
       })
       when is_pid(transport_pid), do: not Map.has_key?(connect_params, "_live_referer")

  defp page_load?(_socket), do: false
end
