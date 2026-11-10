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
  """

  @behaviour NervesHub.DeviceLink.Dispatcher

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.Dispatcher
  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.TimeoutError
  alias NervesHub.DeviceLink.Handlers

  @default_timeout to_timeout(second: 5)
  @default_attempts 2

  @impl Dispatcher
  def call(function, args) do
    function
    |> route_key(args)
    |> Handlers.ordered()
    |> attempt(function, args, attempts())
  end

  defp attempt([], function, _args, _remaining), do: raise(NoHandlersError, function: function)
  defp attempt(_nodes, function, _args, 0), do: raise(NoHandlersError, function: function)

  defp attempt([node | rest], function, args, remaining) do
    timeout = timeout()

    try do
      :erpc.call(node, DeviceLink, function, args, timeout)
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

  # Which device a call concerns, so it lands on the same node each time.
  #
  # A function missing from this list routes arbitrarily, which is only safe
  # while nothing it reaches keeps per-device state on a node.
  # No device is known during a handshake -- that is what is being established --
  # so the certificate stands in for one. Handshakes for the same device then
  # land on the same node.
  defp route_key(:verify_peer, [der | _]), do: :erlang.phash2(der)

  defp route_key(:connect, [device_info | _]), do: device_info.device_id
  defp route_key(:device_join, [device_info | _]), do: device_info.device_id
  defp route_key(:extensions_join, [device_info | _]), do: device_info.device_id

  defp route_key(function, [session | _]) when function in [:device_message, :device_notify, :device_broadcast],
    do: session.device_info.device_id

  defp route_key(function, [extensions | _]) when function in [:extension_message, :extension_info],
    do: extensions_device_id(extensions)

  # authenticate/1 has no device yet, and the connection lifecycle calls are
  # keyed by a connection reference that no node keeps anything under.
  defp route_key(_function, _args), do: nil

  defp extensions_device_id(extensions) when is_map(extensions) do
    Enum.find_value(extensions, fn
      {_key, %{state: %{device_info: %{device_id: device_id}}}} -> device_id
      _ -> nil
    end)
  end

  defp extensions_device_id(_extensions), do: nil

  defp timeout(), do: config(:timeout, @default_timeout)
  defp attempts(), do: config(:attempts, @default_attempts)

  defp config(key, default) do
    Application.get_env(:nerves_hub, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
