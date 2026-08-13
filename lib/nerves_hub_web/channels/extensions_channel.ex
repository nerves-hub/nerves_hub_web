defmodule NervesHubWeb.ExtensionsChannel do
  @moduledoc """
  Carries extension traffic between a device and the platform.

  This channel knows nothing about extensions themselves — not which modules
  serve them, not whether they are attached, not what any message means. It asks
  `NervesHub.DeviceLink` and carries out the effects it gets back: push this to
  the device, send me this term now, send it to me on an interval, stop that
  timer. Every term it handles is opaque to it.
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.DeviceLink
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.join")
  def join("extensions", extension_versions, %{assigns: %{device_info: device_info}} = socket) do
    {attach_list, extensions} = DeviceLink.extensions_join(device_info, extension_versions)

    socket =
      socket
      |> assign(:extensions, extensions)
      |> assign(:extension_timers, %{})

    if not Enum.empty?(attach_list) do
      send(self(), :init_extensions)
    end

    # all devices are lumped into a `extensions` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    :ok = socket.endpoint.unsubscribe("extensions")

    topic = "device:#{device_info.device_id}:extensions"
    :ok = socket.endpoint.subscribe(topic)

    {:ok, attach_list, socket}
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.handle_in")
  def handle_in(scoped_event, payload, socket) do
    case DeviceLink.extension_message(socket.assigns.extensions, scoped_event, payload) do
      {:ok, extensions, effects} ->
        socket
        |> assign(:extensions, extensions)
        |> apply_effects(effects)

      :unknown ->
        # Unknown extension, tell device to detach it
        {:reply, {:error, "detach"}, socket}
    end
  end

  @impl Phoenix.Channel
  def handle_info(:init_extensions, socket) do
    topic = "product:#{socket.assigns.device_info.product_id}:extensions"
    :ok = PubSub.subscribe(NervesHub.PubSub, topic)

    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info({mod, msg}, socket) do
    {:ok, extensions, effects} = DeviceLink.extension_info(socket.assigns.extensions, mod, msg)

    socket
    |> assign(:extensions, extensions)
    |> apply_effects(effects)
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------- effects

  defp apply_effects(socket, effects) do
    {:noreply, Enum.reduce(effects, socket, &apply_effect(&2, &1))}
  end

  defp apply_effect(socket, {:push, event, payload}) do
    push(socket, event, payload)
    socket
  end

  defp apply_effect(socket, {:tick, message}) do
    send(self(), message)
    socket
  end

  defp apply_effect(socket, {:start_timer, key, message, interval_ms}) do
    socket = cancel_timer(socket, key)
    {:ok, ref} = :timer.send_interval(interval_ms, message)

    update_in(socket.assigns.extension_timers, &Map.put(&1, key, ref))
  end

  defp apply_effect(socket, {:cancel_timer, key}) do
    cancel_timer(socket, key)
  end

  defp cancel_timer(socket, key) do
    case Map.pop(socket.assigns.extension_timers, key) do
      {nil, _timers} ->
        socket

      {ref, timers} ->
        _ = :timer.cancel(ref)
        assign(socket, :extension_timers, timers)
    end
  end
end
