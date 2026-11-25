defmodule NervesHub.Telemetry.AsyncTrace do
  @moduledoc """
  `start_async` and `assign_async` for a LiveView or LiveComponent, with the
  task's work in the trace of the callback that started it.

  Every LiveView, LiveComponent and device page tab imports these in place of
  `Phoenix.LiveView`'s (see `NervesHubWeb`), so a bare `start_async` or
  `assign_async` is traced.

  A `start_async` task starts with no trace. `opentelemetry_ecto` looks for one
  in the process that started the task, through `$callers`, but only as each
  query runs, and by then the LiveView's `handle_params` or `handle_event` has
  usually returned: `opentelemetry_phoenix` has ended its span and put back the
  context from before it, which once the page has rendered holds no span. So
  each query in the task starts a trace of its own, sampled as `:default` work
  rather than with the page. If the LiveView is in another callback when the
  query runs, the query joins that callback's trace instead.

  `start_async/4` and `assign_async/4` take the context as the task starts, in
  the LiveView's process, and run the task's work in a span under it, named
  after the LiveView and the async's name:
  `NervesHubWeb.Live.Devices.Index.start_async#update_device_list`, or
  `NervesHubWeb.Live.Firmware.assign_async#failed_installs`. A LiveComponent's
  or device page tab's span is named after the LiveView it's in, as its events
  are, because its socket is the LiveView's. The task's queries, and those of
  any task it starts in turn, are children of that span, and it follows its
  parent's sampling decision. It usually ends after its parent, and Sentry's
  span processor then sends it as a transaction of its own in the parent's
  trace.

  Started where no span is current, as in a `handle_async` or `handle_info`
  callback, or a LiveComponent's `update`, none of which opens one, the span
  starts a trace of its own, which `NervesHub.Telemetry.TracesSampler`
  samples as `:default`.

  A task cancelled with `cancel_async`, or killed with its LiveView, never ends
  its span, so the span is never sent.
  """

  alias Phoenix.LiveView.Socket

  require OpenTelemetry.Tracer, as: Tracer

  @ops [:start_async, :assign_async]
  @span_infixes Enum.map(@ops, &".#{&1}#")

  @doc """
  Starts `func` in a task, as `Phoenix.LiveView.start_async/4` does, with its
  work in a span under the one current here.

  An anonymous function written in place is handed to `start_async` as it is,
  so `start_async` can still warn when it captures the socket. Anything else is
  evaluated here, before the task starts, as `start_async` would.
  """
  defmacro start_async(socket, name, func, opts \\ []) do
    traced(:start_async, socket, name, func, opts)
  end

  @doc """
  Assigns `key_or_keys` from `func` in a task, as
  `Phoenix.LiveView.assign_async/4` does, with its work in a span under the one
  current here.

  As with `start_async/4`, an anonymous function written in place is handed to
  `assign_async` as it is, so it can still warn when it captures the socket.
  """
  defmacro assign_async(socket, key_or_keys, func, opts \\ []) do
    traced(:assign_async, socket, key_or_keys, func, opts)
  end

  defp traced(op, socket, name, func, opts) do
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
      trace = unquote(__MODULE__).trace(traced_socket, unquote(op), traced_name)

      Phoenix.LiveView.unquote(op)(
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

  An async's name often says which one it is as well as what it is: a tuple
  such as `{:send_test, id}`, or a string such as `"load_chart:cpu"`. Only what
  it is goes in the span's name, a tuple's first element or the part of a
  string before its first `:`, as Sentry groups transactions by name. Keys
  assigned together are joined with commas.
  """
  @spec trace(Socket.t(), :start_async | :assign_async, term()) :: {OpenTelemetry.Ctx.t(), String.t()}
  def trace(%Socket{view: view}, op, name) when op in @ops do
    {OpenTelemetry.Ctx.get_current(), "#{inspect(view)}.#{op}##{async_name(name)}"}
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
  def span?(name) when is_binary(name), do: String.contains?(name, @span_infixes)
  def span?(_name), do: false

  defp async_name(name) when is_atom(name), do: Atom.to_string(name)
  defp async_name(name) when is_binary(name), do: name |> String.split(":", parts: 2) |> hd()
  defp async_name(name) when is_tuple(name) and is_atom(elem(name, 0)), do: name |> elem(0) |> Atom.to_string()
  defp async_name(names) when is_list(names), do: Enum.map_join(names, ",", &async_name/1)
  defp async_name(name), do: inspect(name)
end
