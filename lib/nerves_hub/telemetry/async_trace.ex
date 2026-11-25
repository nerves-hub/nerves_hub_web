defmodule NervesHub.Telemetry.AsyncTrace do
  @moduledoc """
  `start_async` for a LiveView or LiveComponent, with the task's work in the
  trace of the callback that started it.

  A `start_async` task starts with no trace. `opentelemetry_ecto` looks for one
  in the process that started the task, through `$callers`, but only as each
  query runs, and by then the LiveView's `handle_params` or `handle_event` has
  usually returned: `opentelemetry_phoenix` has ended its span and put back the
  context from before it, which once the page has rendered holds no span. So
  each query in the task starts a trace of its own, sampled as `:default` work
  rather than with the page. If the LiveView is in another callback when the
  query runs, the query joins that callback's trace instead.

  `start_async/4` takes the context as the task starts, in the LiveView's
  process, and runs the task's work in a span under it, named after the
  LiveView and the async's name:
  `NervesHubWeb.Live.Devices.Index.start_async#update_device_list`. The task's
  queries, and those of any task it starts in turn, are children of that span,
  and it follows its parent's sampling decision. It usually ends after its
  parent, and Sentry's span processor then sends it as a transaction of its
  own in the parent's trace.

  Started where no span is current, as in a `handle_async` callback or a
  `handle_info` that opens none, the span starts a trace of its own, which
  `NervesHub.Telemetry.TracesSampler` samples as `:default`.

  A task cancelled with `cancel_async`, or killed with its LiveView, never ends
  its span, so the span is never sent.
  """

  alias Phoenix.LiveView.Socket

  require OpenTelemetry.Tracer, as: Tracer

  @span_infix ".start_async#"

  @doc """
  Starts `func` in a task, as `Phoenix.LiveView.start_async/4` does, with its
  work in a span under the one current here.

  An anonymous function written in place is handed to `start_async` as it is,
  so `start_async` can still warn when it captures the socket. Anything else is
  evaluated here, before the task starts, as `start_async` would.
  """
  defmacro start_async(socket, name, func, opts \\ []) do
    {bindings, func} =
      case func do
        {kind, _meta, _args} when kind in [:fn, :&] ->
          {[], func}

        _expression ->
          var = Macro.unique_var(:func, __MODULE__)
          {[quote(do: unquote(var) = unquote(func))], var}
      end

    quote do
      require Phoenix.LiveView

      traced_socket = unquote(socket)
      traced_name = unquote(name)
      unquote_splicing(bindings)
      trace = unquote(__MODULE__).trace(traced_socket, traced_name)

      Phoenix.LiveView.start_async(
        traced_socket,
        traced_name,
        fn -> unquote(__MODULE__).run(trace, unquote(func)) end,
        unquote(opts)
      )
    end
  end

  @doc """
  The context current in the caller, and the name of the span the task's work
  runs in.

  An async's name is often a tuple whose first element says what it is and
  whose others say which one, such as `{:send_test, id}`. Only the first goes
  in the span's name, as Sentry groups transactions by name.
  """
  @spec trace(Socket.t(), term()) :: {OpenTelemetry.Ctx.t(), String.t()}
  def trace(%Socket{view: view}, name) do
    {OpenTelemetry.Ctx.get_current(), inspect(view) <> @span_infix <> async_name(name)}
  end

  @doc """
  Runs `func` in a span named by `trace`, under the context it was taken in.

  The span ends, and the context is put back, however `func` finishes. One
  that raises, throws or exits marks the span as failed and is passed on.
  """
  @spec run({OpenTelemetry.Ctx.t(), String.t()}, (-> result)) :: result when result: term()
  def run({ctx, span_name}, func) do
    Tracer.with_span ctx, span_name, %{} do
      try do
        func.()
      catch
        kind, reason ->
          Tracer.set_status(OpenTelemetry.status(:error, Exception.format_banner(kind, reason, __STACKTRACE__)))
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  @doc """
  Whether a span is the work of an async task started here.
  """
  @spec span?(term()) :: boolean()
  def span?(name) when is_binary(name), do: String.contains?(name, @span_infix)
  def span?(_name), do: false

  defp async_name(name) when is_atom(name), do: Atom.to_string(name)
  defp async_name(name) when is_binary(name), do: name
  defp async_name(name) when is_tuple(name) and is_atom(elem(name, 0)), do: name |> elem(0) |> Atom.to_string()
  defp async_name(name), do: inspect(name)
end
