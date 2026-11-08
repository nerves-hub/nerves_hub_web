defmodule NervesHubWeb.DeviceChannel do
  @moduledoc """
  Primary websocket channel for device communication.

  This channel decides nothing. It hands everything to `NervesHub.DeviceLink` —
  the device joined, the device said this, something addressed the device, a
  broadcast needs handling — and carries out the effects it gets back. The
  session it holds between messages is opaque to it.

  That is deliberate: it means holding a device's connection does not require
  the platform's code, which is what allows the connection to be held somewhere
  the platform is not.

  When the platform does not answer, what the device said or was sent is dropped
  and the session stays as it was; see `NervesHubWeb.Channels.Platform`. The
  device keeps its connection.

  # Fastlaned Messages

  - identify
  - reboot
  - update (scheduled and manual)
  - archive (but sent from within the channel process)
  - fwup_public_keys (but sent from within the channel process)
  - archive_public_keys (but sent from within the channel process)

  # Intercepted Messages

  - updated
  - deployment_updated
  """

  use Phoenix.Channel
  use OpenTelemetryDecorator

  alias NervesHub.DeviceLink.Client, as: DeviceLink
  alias NervesHubWeb.Channels.Effects
  alias NervesHubWeb.Channels.Platform

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device:" <> _device_id, params, %{assigns: %{device_info: device_info}} = socket) do
    Logger.metadata(device_id: device_info.device_id, device_identifier: device_info.device_identifier)

    case Platform.ask(socket, :device_join, fn -> DeviceLink.device_join(device_info, params) end) do
      {:ok, session, effects} ->
        socket =
          socket
          |> assign(:session, session)
          |> Effects.init()
          |> Effects.apply_all(effects)

        {:ok, socket}

      {:error, _error} ->
        {:error, %{error: "could not connect"}}

      # Refused, not crashed: the socket stays up, and the client joins again on
      # its own.
      :unanswered ->
        {:error, %{error: "could not connect"}}
    end
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_in")
  def handle_in(event, payload, socket) do
    advance(socket, :device_message, &DeviceLink.device_message(&1, event, payload))
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_info")
  def handle_info(message, socket) do
    # Timers armed through `Effects` deliver in an envelope; the rest passes through.
    case Effects.timer_fired(socket, message) do
      {:deliver, message, socket} -> advance(socket, :device_notify, &DeviceLink.device_notify(&1, message))
      {:drop, socket} -> {:noreply, socket}
      :not_timer -> advance(socket, :device_notify, &DeviceLink.device_notify(&1, message))
    end
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_out")
  def handle_out(event, payload, socket) do
    advance(socket, :device_broadcast, &DeviceLink.device_broadcast(&1, event, payload))
  end

  # For a timer, `socket` is the one `Effects.timer_fired/2` returned, which has
  # already re-armed an interval. Keeping it when the platform does not answer
  # keeps the timer.
  defp advance(socket, function, fun) do
    case Platform.ask(socket, function, fn -> fun.(socket.assigns.session) end) do
      {session, effects} ->
        socket =
          socket
          |> assign(:session, session)
          |> Effects.apply_all(effects)

        {:noreply, socket}

      :unanswered ->
        {:noreply, socket}
    end
  end
end
