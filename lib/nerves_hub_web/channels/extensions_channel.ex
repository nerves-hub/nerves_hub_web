defmodule NervesHubWeb.ExtensionsChannel do
  @moduledoc """
  Carries extension traffic between a device and the platform.

  This channel knows nothing about extensions themselves — not which modules
  serve them, not whether they are attached, not what any message means. It asks
  `NervesHub.DeviceLink` and carries out the effects it gets back: push this to
  the device, send me this term now, send it to me on an interval, stop that
  timer. Every term it handles is opaque to it.

  When the platform does not answer, the message is dropped and the extensions
  keep the state they had; see `NervesHubWeb.Channels.Platform`. The device keeps
  its connection.
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.DeviceLink.Client, as: DeviceLink
  alias NervesHub.Extensions
  alias NervesHubWeb.Channels.Effects
  alias NervesHubWeb.Channels.Platform
  alias Phoenix.Socket.Broadcast

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.join")
  def join("extensions", extension_versions, %{assigns: %{device_info: device_info}} = socket) do
    case Platform.ask(socket, :extensions_join, fn ->
           DeviceLink.extensions_join(device_info, extension_versions)
         end) do
      {attach_list, extensions} ->
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

      # Refused, not crashed: the device channel and the socket stay up, and the
      # client joins again on its own.
      :unanswered ->
        {:error, %{error: "could not connect"}}
    end
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.ExtensionsChannel.handle_in")
  def handle_in(scoped_event, payload, socket) do
    case Platform.ask(socket, :extension_message, fn ->
           DeviceLink.extension_message(socket.assigns.extensions, scoped_event, payload)
         end) do
      {:ok, extensions, effects} ->
        socket
        |> assign(:extensions, extensions)
        |> apply_effects(effects)

      :unknown ->
        # Unknown extension, tell device to detach it
        {:reply, {:error, "detach"}, socket}

      :unanswered ->
        {:noreply, socket}
    end
  end

  @impl Phoenix.Channel
  def handle_info(:init_extensions, socket) do
    :ok = Extensions.PubSub.subscribe_product(socket.assigns.device_info.product_id)

    {:noreply, socket}
  end

  @decorate with_span("Channels.ExtensionsChannel.handle_info[Broadcast]")
  def handle_info(%Broadcast{event: event, payload: payload}, socket) do
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

  # For a timer, `socket` is the one `Effects.timer_fired/2` returned, which has
  # already re-armed an interval. Keeping it when the platform does not answer
  # keeps the timer: the delivery is dropped, the next one still comes.
  defp extension_info(socket, mod, msg) do
    case Platform.ask(socket, :extension_info, fn ->
           DeviceLink.extension_info(socket.assigns.extensions, mod, msg)
         end) do
      {:ok, extensions, effects} ->
        socket
        |> assign(:extensions, extensions)
        |> apply_effects(effects)

      :unanswered ->
        {:noreply, socket}
    end
  end

  defp apply_effects(socket, effects), do: {:noreply, Effects.apply_all(socket, effects)}
end
