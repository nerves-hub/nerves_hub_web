defmodule NervesHubWeb.Channels.Platform do
  @moduledoc """
  Asks `NervesHub.DeviceLink` something on behalf of a connected device, and
  says so plainly when no answer came.

  The platform can fail to answer in two ways that say nothing about the
  device: no node could be reached, or the node that took the call did not
  finish in time. Raising in either case would end the process holding the
  connection, and with it a healthy connection, which the device then rebuilds
  -- adding load at the moment the platform is shortest of it. So both come
  back as `:unanswered`, and what that costs is the caller's decision: one
  extension message, a join, or a device channel the device then joins again.

  An exception the platform raised is not caught. That is an answer, and a bug
  should not look like an outage.

  Every unanswered call emits `[:nerves_hub, :device_link, :unanswered]`, with
  the `function`, a `reason` of `:no_handlers` or `:timeout`, the `error`, and
  the `device_id`, so none is ever silent.
  """

  alias NervesHub.DeviceLink.Dispatcher.NoHandlersError
  alias NervesHub.DeviceLink.Dispatcher.TimeoutError
  alias Phoenix.Socket

  @doc """
  Run `call`, which makes the `function` call through
  `NervesHub.DeviceLink.Client`, and return its answer or `:unanswered`.
  """
  @spec ask(Socket.t(), function :: atom(), call :: (-> answer)) :: answer | :unanswered
        when answer: term()
  def ask(socket, function, call) do
    call.()
  rescue
    error in [NoHandlersError, TimeoutError] ->
      :telemetry.execute([:nerves_hub, :device_link, :unanswered], %{count: 1}, %{
        function: function,
        reason: reason(error),
        error: error,
        device_id: device_id(socket)
      })

      :unanswered
  end

  defp reason(%TimeoutError{}), do: :timeout
  defp reason(%NoHandlersError{}), do: :no_handlers

  defp device_id(%{assigns: %{device_info: %{device_id: device_id}}}), do: device_id
  defp device_id(_socket), do: nil
end
