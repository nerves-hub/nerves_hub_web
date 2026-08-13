defmodule NervesHubWeb.Channels.Effects do
  @moduledoc """
  Carries out the effects `NervesHub.DeviceLink` asks for, on a channel.

  See `NervesHub.DeviceLink.Effect` for the vocabulary. Nothing here inspects a
  message or a timer key — they are opaque terms that get sent and filed. That
  is the point: a channel using this module holds a device connection without
  depending on anything that decides what should happen over it.

  Timers are tracked per channel process under the `:link_timers` assign, so
  `:cancel_timer` needs only the key that started it.
  """

  alias Phoenix.Channel
  alias Phoenix.Socket

  @timers :link_timers

  @doc "Prepare a socket to have effects applied to it."
  @spec init(Socket.t()) :: Socket.t()
  def init(socket), do: Socket.assign(socket, @timers, %{})

  @doc "Apply effects in order, returning the updated socket."
  @spec apply_all(Socket.t(), [NervesHub.DeviceLink.Effect.t()]) :: Socket.t()
  def apply_all(socket, effects), do: Enum.reduce(effects, socket, &apply_one(&2, &1))

  defp apply_one(socket, {:push, event, payload}) do
    :ok = Channel.push(socket, event, payload)
    socket
  end

  defp apply_one(socket, {:subscribe, topic}) do
    :ok = Phoenix.PubSub.subscribe(NervesHub.PubSub, topic)
    socket
  end

  defp apply_one(socket, {:unsubscribe, topic}) do
    :ok = Phoenix.PubSub.unsubscribe(NervesHub.PubSub, topic)
    socket
  end

  defp apply_one(socket, {:send_self, message}) do
    send(self(), message)
    socket
  end

  defp apply_one(socket, {:send_after, key, message, delay_ms}) do
    socket = cancel(socket, key)
    ref = Process.send_after(self(), message, delay_ms)

    put_timer(socket, key, {:send_after, ref})
  end

  defp apply_one(socket, {:start_timer, key, message, interval_ms}) do
    socket = cancel(socket, key)
    {:ok, ref} = :timer.send_interval(interval_ms, message)

    put_timer(socket, key, {:interval, ref})
  end

  defp apply_one(socket, {:cancel_timer, key}), do: cancel(socket, key)

  defp put_timer(socket, key, ref) do
    Socket.assign(socket, @timers, Map.put(socket.assigns[@timers] || %{}, key, ref))
  end

  defp cancel(socket, key) do
    case Map.pop(socket.assigns[@timers] || %{}, key) do
      {nil, _timers} ->
        socket

      {ref, timers} ->
        _ = cancel_ref(ref)
        Socket.assign(socket, @timers, timers)
    end
  end

  defp cancel_ref({:send_after, ref}), do: Process.cancel_timer(ref)
  defp cancel_ref({:interval, ref}), do: :timer.cancel(ref)
end
