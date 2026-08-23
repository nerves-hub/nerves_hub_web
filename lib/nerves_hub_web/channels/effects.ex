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

  alias NervesHub.DeviceLink.Effect
  alias NervesHubWeb.Channels.Scrollback
  alias Phoenix.Channel
  alias Phoenix.Socket

  @timers :link_timers
  @scrollback :link_scrollback

  @doc "Prepare a socket to have effects applied to it."
  @spec init(Socket.t()) :: Socket.t()
  def init(socket), do: Socket.assign(socket, @timers, %{})

  @doc "Apply effects in order, returning the updated socket."
  @spec apply_all(Socket.t(), [Effect.t()]) :: Socket.t()
  def apply_all(socket, effects), do: Enum.reduce(effects, socket, &apply_one(&2, &1))

  @doc """
  Re-arm a repeating timer whose message has just arrived.

  `:start_timer` promises delivery every `interval_ms`, and the VM's timer
  wheel only does one-shots, so the repeat has to be re-armed somewhere. It
  happens here, before the message is dispatched, rather than by asking the
  extension to re-arm itself: `NervesHub.Extensions.Dispatch` swallows an
  extension that raises, and a re-arm missed that way would stop the timer for
  the life of the connection with nothing to show for it.

  Messages that are not a live interval's are returned untouched.
  """
  @spec reschedule(Socket.t(), message :: term()) :: Socket.t()
  def reschedule(socket, message) do
    socket.assigns[@timers]
    |> Kernel.||(%{})
    |> Enum.find(fn {_key, timer} -> match?({:interval, _ref, ^message, _ms}, timer) end)
    |> case do
      nil ->
        socket

      {key, {:interval, _ref, _message, interval_ms}} ->
        put_timer(socket, key, {:interval, Process.send_after(self(), message, interval_ms), message, interval_ms})
    end
  end

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

  # `:timer.send_interval/2` spawns a process per interval, and that process
  # lives as long as the connection does. One per device for the health check
  # alone came to 1425 processes and about 40MB on a production device node.
  # `Process.send_after/3` uses the VM's timer wheel and costs no process at
  # all, so the repeat is re-armed in `reschedule/2` instead.
  defp apply_one(socket, {:start_timer, key, message, interval_ms}) do
    socket = cancel(socket, key)
    ref = Process.send_after(self(), message, interval_ms)

    put_timer(socket, key, {:interval, ref, message, interval_ms})
  end

  defp apply_one(socket, {:cancel_timer, key}), do: cancel(socket, key)

  defp apply_one(socket, {:scrollback_append, data}) do
    Socket.assign(socket, @scrollback, Scrollback.append(scrollback(socket), data))
  end

  defp apply_one(socket, {:scrollback_replay, pid}) do
    send(pid, {:cache, Scrollback.text(scrollback(socket))})
    socket
  end

  defp apply_one(socket, {:scrollback_clear}) do
    Socket.assign(socket, @scrollback, Scrollback.new())
  end

  defp scrollback(socket), do: socket.assigns[@scrollback] || Scrollback.new()

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
  defp cancel_ref({:interval, ref, _message, _interval_ms}), do: Process.cancel_timer(ref)
end
