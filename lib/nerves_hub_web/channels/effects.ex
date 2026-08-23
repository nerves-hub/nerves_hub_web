defmodule NervesHubWeb.Channels.Effects do
  @moduledoc """
  Carries out the effects `NervesHub.DeviceLink` asks for, on a channel.

  See `NervesHub.DeviceLink.Effect` for the vocabulary. Nothing here inspects a
  message or a timer key — they are opaque terms that get sent and filed. That
  is the point: a channel using this module holds a device connection without
  depending on anything that decides what should happen over it.

  Timers are tracked per channel process under the `:link_timers` assign, so
  `:cancel_timer` needs only the key that started it.

  ## Timer deliveries

  A timer armed here delivers `{:timeout, ref, {key, message}}` — the envelope
  `:erlang.start_timer/3` produces — rather than the bare message. Channels
  hand these to `timer_fired/2`, which re-arms intervals, retires one-shots,
  unwraps the message, and drops deliveries from timers that no longer exist.
  Matching on the ref keeps a timer firing distinct from any other way the
  same message term might arrive.
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
  Recognize a timer delivery, keep the timer's promise, and unwrap its message.

  Channels offer this every info message before handling it themselves:

    * `{:deliver, message, socket}` — a live timer fired. An interval has been
      re-armed, a one-shot's bookkeeping retired; dispatch `message`.
    * `{:drop, socket}` — the timer this came from was cancelled or replaced
      between firing and delivery. There is nothing to act on.
    * `:not_timer` — not a timer delivery; handle the message as usual.
  """
  @spec timer_fired(Socket.t(), message :: term()) ::
          {:deliver, term(), Socket.t()} | {:drop, Socket.t()} | :not_timer
  def timer_fired(socket, {:timeout, ref, {key, message}}) when is_reference(ref) do
    case timers(socket)[key] do
      {:interval, ^ref, interval_ms} ->
        {:deliver, message, put_timer(socket, key, {:interval, arm(key, message, interval_ms), interval_ms})}

      {:send_after, ^ref} ->
        # Fired and delivered — the entry is done.
        {:deliver, message, Socket.assign(socket, @timers, Map.delete(timers(socket), key))}

      _ ->
        {:drop, socket}
    end
  end

  def timer_fired(_socket, _message), do: :not_timer

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

    put_timer(socket, key, {:send_after, arm(key, message, delay_ms)})
  end

  # `:timer.send_interval/2` spawns a process per interval that lives as long
  # as the connection (about 40MB across a production device node). The VM's
  # timer wheel costs no process but only does one-shots, so `timer_fired/2`
  # re-arms on each delivery.
  defp apply_one(socket, {:start_timer, key, message, interval_ms}) do
    socket = cancel(socket, key)

    put_timer(socket, key, {:interval, arm(key, message, interval_ms), interval_ms})
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

  # `:erlang.start_timer/3` stamps the timer's ref into what it delivers,
  # letting `timer_fired/2` recognize a firing by ref rather than by message.
  defp arm(key, message, ms), do: :erlang.start_timer(ms, self(), {key, message})

  defp scrollback(socket), do: socket.assigns[@scrollback] || Scrollback.new()

  defp timers(socket), do: socket.assigns[@timers] || %{}

  defp put_timer(socket, key, timer) do
    Socket.assign(socket, @timers, Map.put(timers(socket), key, timer))
  end

  defp cancel(socket, key) do
    case Map.pop(timers(socket), key) do
      {nil, _timers} ->
        socket

      {timer, timers} ->
        _ = cancel_ref(timer)
        Socket.assign(socket, @timers, timers)
    end
  end

  defp cancel_ref({:send_after, ref}), do: Process.cancel_timer(ref)
  defp cancel_ref({:interval, ref, _interval_ms}), do: Process.cancel_timer(ref)
end
