defmodule NervesHub.DeviceLink.Dispatcher.NoHandlersError do
  @moduledoc """
  Raised when no node is available to service a `NervesHub.DeviceLink` call.

  Callers holding a device connection decide what this means. Refusing a device
  that cannot be authenticated is correct; dropping a device that already has a
  healthy connection because the platform is briefly unreachable is not.
  """

  defexception [:function]

  @impl Exception
  def message(%{function: function}) do
    "no DeviceLink handler nodes available for #{function}"
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
  matters. A call that fails for a transport reason is retried on the next node
  in the ring, up to a cap. A call that fails because the platform itself raised
  is not retried — that is an answer, not an outage.
  """

  @behaviour NervesHub.DeviceLink.Dispatcher

  alias NervesHub.DeviceLink
  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Handlers

  @default_timeout to_timeout(second: 5)
  @default_attempts 2

  @impl NervesHub.DeviceLink.Dispatcher
  def call(function, args) do
    function
    |> route_key(args)
    |> Handlers.ordered()
    |> attempt(function, args, attempts())
  end

  defp attempt([], function, _args, _remaining), do: raise(NoHandlersError, function: function)
  defp attempt(_nodes, function, _args, 0), do: raise(NoHandlersError, function: function)

  defp attempt([node | rest], function, args, remaining) do
    :erpc.call(node, DeviceLink, function, args, timeout())
  catch
    # Only transport failures are retried. A remote exception propagates
    # untouched, so a bug in the platform does not look like an outage.
    :error, {:erpc, reason} when reason in [:noconnection, :timeout] ->
      :telemetry.execute([:nerves_hub, :device_link, :dispatch_failure], %{count: 1}, %{
        node: node,
        reason: reason,
        function: function
      })

      attempt(rest, function, args, remaining - 1)
  end

  # Which device a call concerns, so it lands on the same node each time.
  #
  # A function missing from this list routes arbitrarily, which is only safe
  # while nothing it reaches keeps per-device state on a node.
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
