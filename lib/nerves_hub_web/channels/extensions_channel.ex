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

  alias NervesHub.DeviceLink.Client, as: DeviceLink
  alias NervesHub.Devices.DeviceMessages
  alias NervesHub.Extensions
  alias NervesHub.Helpers.Logging
  alias NervesHubWeb.Channels.Effects
  alias Phoenix.PubSub
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.join")
  def join("extensions", extension_versions, %{assigns: %{device_info: device_info}} = socket) do
    {attach_list, extensions} = DeviceLink.extensions_join(device_info, extension_versions)

    socket =
      socket
      |> assign(:extensions, extensions)
      |> Effects.init()

    if not Enum.empty?(attach_list) do
      send(self(), :init_extensions)
    end

    # all devices are lumped into a `extensions` topic (the name used in join/3)
    # this can be a security issue as pubsub messages can be sent to all connected devices
    # additionally, this topic isn't needed or used, so we can unsubscribe from it
    :ok = socket.endpoint.unsubscribe("extensions")

    :ok = Extensions.PubSub.subscribe_device(device_info.device_id)

    {:ok, attach_list, socket}
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.handle_in")
  def handle_in(scoped_event, payload, socket) do
    :ok = DeviceMessages.record(device_info(socket), :received, :extensions, scoped_event, payload)

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
    :ok = Extensions.PubSub.subscribe_product(socket.assigns.device_info.product_id)

    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
    :ok = DeviceMessages.record(device_info(socket), :sent, :extensions, event, payload)

    push(socket, event, payload)
    {:noreply, socket}
  end

  # A timer armed through `Effects` delivering; `timer_fired/2` re-arms it.
  @decorate with_span("Channels.ExtensionsChannel.handle_info[timer]")
  def handle_info({:timeout, _ref, _payload} = timer, socket) do
    case Effects.timer_fired(socket, timer) do
      {:deliver, {mod, msg}, socket} -> extension_info(socket, mod, msg)
      {:drop, socket} -> {:noreply, socket}
      :not_timer -> {:noreply, socket}
    end
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[extension]")
  def handle_info({mod, msg}, socket) do
    extension_info(socket, mod, msg)
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp extension_info(socket, mod, msg) do
    {:ok, extensions, effects} = DeviceLink.extension_info(socket.assigns.extensions, mod, msg)

    socket
    |> assign(:extensions, extensions)
    |> apply_effects(effects)
  end

  defp apply_effects(socket, effects) do
    device_info = device_info(socket)

    Enum.each(effects, fn
      {:push, event, payload} -> DeviceMessages.record(device_info, :sent, :extensions, event, payload)
      _effect -> :ok
    end)

    {:noreply, Effects.apply_all(socket, effects)}
  end

  defp device_info(socket), do: socket.assigns.device_info
end
