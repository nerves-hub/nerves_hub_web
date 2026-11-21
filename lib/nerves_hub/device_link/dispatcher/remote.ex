defmodule NervesHub.DeviceLink.Dispatcher.NoHandlersError do
  @moduledoc """
  Raised when no node is available to service a `NervesHub.DeviceLink` call.

  Callers holding a device connection decide what this means. Refusing a device
  that cannot be authenticated is correct; dropping a device that already has a
  healthy connection because the platform is briefly unreachable is not.

  A node that was reached but did not answer in time raises
  `NervesHub.DeviceLink.Dispatcher.TimeoutError` instead, so the two read
  differently wherever they are reported.
  """

  defexception [:function]

  @impl Exception
  def message(%{function: function}) do
    "no DeviceLink handler nodes available for #{function}"
  end
end

defmodule NervesHub.DeviceLink.Dispatcher.TimeoutError do
  @moduledoc """
  Raised when the node a `NervesHub.DeviceLink` call was sent to did not answer
  in time.

  Not the same as `NervesHub.DeviceLink.Dispatcher.NoHandlersError`. The node
  was there and took the call, and is most likely still working on it: a
  timeout abandons the reply, not the work. What it means is that the platform
  is slow, not that it is gone.
  """

  defexception [:function, :node, :timeout]

  @impl Exception
  def message(%{function: function, node: node, timeout: timeout}) do
    "DeviceLink #{function} did not finish on #{node} within #{timeout} ms"
  end
end

defmodule NervesHub.DeviceLink.Dispatcher.Remote do
  @moduledoc """
  Runs `NervesHub.DeviceLink` calls on a node that carries the platform stack.

  For callers that are not such a node. A node holding the database and the
  contexts should use `NervesHub.DeviceLink.Dispatcher.Local` instead — there is
  nothing to gain from a hop when everything needed is already in the VM.

  Calls route deterministically on the device they concern, so one device's
  calls land on one node; see `NervesHub.DeviceLink.Handlers` for why that
  matters. A call that could not reach its node is retried on the next node in
  the ring, up to a cap, and raises `NoHandlersError` when none is left. A call
  that reached its node and did not finish in time is not retried: it raises
  `TimeoutError`. A call that fails because the platform itself raised is not
  retried either — that is an answer, not an outage.

  Each call carries the caller's trace with it, and `run/3` continues it on the
  node that takes the call. So what the platform does for a device, its queries
  included, lands in the trace of the device message that caused it.
  """

  @behaviour NervesHub.DeviceLink.Dispatcher

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.DeviceInfo
  alias NervesHub.DeviceLink.Dispatcher
  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.TimeoutError
  alias NervesHub.DeviceLink.Handlers

  require OpenTelemetry.Tracer, as: Tracer

  @default_timeout to_timeout(second: 5)
  @default_attempts 2

  @impl Dispatcher
  def call(function, args) do
    function
    |> route_key(args)
    |> Handlers.ordered()
    |> attempt(function, args, attempts())
  end

  @doc """
  Runs a `NervesHub.DeviceLink` call that `call/2` sent here from another node.

  `trace_context` is the calling node's trace, as
  `:otel_propagator_text_map.inject/1` wrote it. The span opened here, named
  `DeviceLink.<function>`, is a child of the caller's span, and follows the
  caller's sampling decision: a trace the caller kept is kept here, and one it
  dropped is dropped here too. With no trace to continue, the span starts one.
  It carries the device's ids (`NervesHub.DeviceLink.DeviceInfo.trace_attributes/1`)
  when the call is about a device, and the event or extension when it's about
  one of those.

  ## Called over `:erpc` by other applications in the cluster

  **Its only caller in nerves_hub_web is `call/2`, which sends it to another
  node, and that is expected. It is not unused. Do not remove it.** See
  "Cross-application contracts" in `AGENTS.md`.

  It returns what the `DeviceLink` function returns, and raises what it raises,
  unchanged. Its name and arguments are the published part: a caller deployed
  with this `call/2` sends `run/3` to every node it calls. A node from before
  `run/3` answers `:undef`, and `call/2` then calls `DeviceLink` directly, so the
  platform has to be deployed first only for the trace to carry across.
  """
  @spec run(trace_context :: [{String.t(), String.t()}], function :: atom(), args :: [term()]) :: term()
  def run(trace_context, function, args) do
    ctx = :otel_propagator_text_map.extract_to(:otel_ctx.new(), trace_context)

    Tracer.with_span ctx, "DeviceLink.#{function}", %{kind: :server, attributes: trace_attributes(function, args)} do
      try do
        apply(DeviceLink, function, args)
      catch
        # Raised again as it came, so the caller sees exactly what it would have
        # seen calling `DeviceLink` itself.
        kind, reason ->
          Tracer.set_status(:error, Exception.format_banner(kind, reason, __STACKTRACE__))
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  defp attempt([], function, _args, _remaining), do: raise(NoHandlersError, function: function)
  defp attempt(_nodes, function, _args, 0), do: raise(NoHandlersError, function: function)

  defp attempt([node | rest], function, args, remaining) do
    timeout = timeout()

    try do
      run_on(node, function, args, timeout)
    catch
      # The node could not be reached, so the call never started there. Retried
      # on the next node. A remote exception is not caught here, so a bug in the
      # platform does not look like an outage.
      :error, {:erpc, :noconnection} ->
        :telemetry.execute([:nerves_hub, :device_link, :dispatch_failure], %{count: 1}, %{
          node: node,
          reason: :noconnection,
          function: function
        })

        attempt(rest, function, args, remaining - 1)

      # The node took the call and did not answer in time. :erpc abandons the
      # reply, not the work, so the node is most likely still running it, and
      # sending it to another node doubles the work at the moment the platform
      # is slowest. Decided per function, and the answer is the same for all:
      #
      #   verify_peer, authenticate -- can register a certificate or a device,
      #     so two copies racing can fail a handshake the first would have
      #     passed. The device retries the whole connection itself, with backoff.
      #   connect -- starts a connection row; a second run replaces its id and
      #     leaves the first answer pointing at nothing.
      #   heartbeat, disconnect -- idempotent, but the first will almost
      #     certainly still land, and the next heartbeat is an interval away.
      #   device_join, device_message, device_notify, device_broadcast -- record
      #     what the device said and act on it, so they are not idempotent.
      #   extensions_join, extension_message, extension_info -- not idempotent
      #     either, and slow is what extension work is when the platform is busy.
      :error, {:erpc, :timeout} ->
        :telemetry.execute([:nerves_hub, :device_link, :dispatch_timeout], %{count: 1}, %{
          node: node,
          timeout: timeout,
          function: function
        })

        raise TimeoutError, function: function, node: node, timeout: timeout
    end
  end

  # A node on a release from before `run/3` answers `:undef` straight away, and
  # gets the call the way it used to, without the trace. That keeps calls working
  # while a caller is ahead of the platform, during a rollout or after a rollback.
  # An `:undef` from anywhere else, such as a `DeviceLink` function the node has
  # never heard of, is raised as before.
  defp run_on(node, function, args, timeout) do
    :erpc.call(node, __MODULE__, :run, [:otel_propagator_text_map.inject([]), function, args], timeout)
  catch
    :error, {:exception, :undef, [{__MODULE__, :run, _args, _location} | _stack]} ->
      :erpc.call(node, DeviceLink, function, args, timeout)
  end

  # Which device a call concerns, so it lands on the same node each time.
  #
  # A function missing from `device_info/2` routes arbitrarily, which is only
  # safe while nothing it reaches keeps per-device state on a node.
  # No device is known during a handshake -- that is what is being established --
  # so the certificate stands in for one. Handshakes for the same device then
  # land on the same node.
  defp route_key(:verify_peer, [der | _]), do: :erlang.phash2(der)

  defp route_key(function, args) do
    case device_info(function, args) do
      nil -> nil
      device_info -> device_info.device_id
    end
  end

  # The device a call concerns, where its arguments say.
  defp device_info(function, [device_info | _]) when function in [:connect, :device_join, :extensions_join],
    do: device_info

  defp device_info(function, [session | _]) when function in [:device_message, :device_notify, :device_broadcast],
    do: session.device_info

  defp device_info(function, [extensions | _]) when function in [:extension_message, :extension_info],
    do: extensions_device_info(extensions)

  # authenticate/1 has no device yet, and the connection lifecycle calls are
  # keyed by a connection reference that no node keeps anything under.
  defp device_info(_function, _args), do: nil

  defp extensions_device_info(extensions) when is_map(extensions) do
    Enum.find_value(extensions, fn
      {_key, %{state: %{device_info: %{device_id: _device_id} = device_info}}} -> device_info
      _ -> nil
    end)
  end

  defp extensions_device_info(_extensions), do: nil

  defp trace_attributes(function, args) do
    device =
      case device_info(function, args) do
        %DeviceInfo{} = device_info -> DeviceInfo.trace_attributes(device_info)
        _ -> %{}
      end

    Map.merge(device, subject_attributes(function, args))
  end

  defp subject_attributes(function, [_session_or_extensions, event | _])
       when function in [:device_message, :device_broadcast, :extension_message] and is_binary(event),
       do: %{"nerves_hub.channel.event": event}

  defp subject_attributes(:extension_info, [_extensions, module | _]) when is_atom(module),
    do: %{"nerves_hub.extension": inspect(module)}

  defp subject_attributes(_function, _args), do: %{}

  defp timeout(), do: config(:timeout, @default_timeout)
  defp attempts(), do: config(:attempts, @default_attempts)

  defp config(key, default) do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
