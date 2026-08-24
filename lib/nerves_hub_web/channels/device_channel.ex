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
  alias NervesHub.Devices.DeviceMessages
  alias NervesHubWeb.Channels.Effects

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device:" <> _device_id, params, %{assigns: %{device_info: device_info}} = socket) do
    Logger.metadata(device_id: device_info.device_id, device_identifier: device_info.device_identifier)

    case DeviceLink.device_join(device_info, params) do
      {:ok, session, effects} ->
        :ok = DeviceMessages.record(device_info, :received, :device, "join", params)
        :ok = record_pushes(device_info, effects)

        socket =
          socket
          |> assign(:session, session)
          |> Effects.init()
          |> Effects.apply_all(effects)

        {:ok, socket}

      {:error, _error} ->
        {:error, %{error: "could not connect"}}
    end
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_in")
  def handle_in(event, payload, socket) do
    :ok = DeviceMessages.record(device_info(socket), :received, :device, event, payload)

    advance(socket, &DeviceLink.device_message(&1, event, payload))
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_info")
  def handle_info(message, socket) do
    # Timers armed through `Effects` deliver in an envelope; the rest passes through.
    case Effects.timer_fired(socket, message) do
      {:deliver, message, socket} -> advance(socket, &DeviceLink.device_notify(&1, message))
      {:drop, socket} -> {:noreply, socket}
      :not_timer -> advance(socket, &DeviceLink.device_notify(&1, message))
    end
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_out")
  def handle_out(event, payload, socket) do
    advance(socket, &DeviceLink.device_broadcast(&1, event, payload))
  end

  defp advance(socket, fun) do
    {session, effects} = fun.(socket.assigns.session)

    :ok = record_pushes(session.device_info, effects)

    socket =
      socket
      |> assign(:session, session)
      |> Effects.apply_all(effects)

    {:noreply, socket}
  end

  # Only pushes cross the wire. The rest of the effect vocabulary — subscribing,
  # timers, scrollback — never reaches the device and has nothing to record.
  #
  # This does not see the platform's fastlaned sends (identify, reboot, update,
  # archive, the public keys): Phoenix delivers those from the broadcast to the
  # transport without this process running. They are recorded where they are
  # broadcast instead. See `NervesHub.Devices.DeviceMessages`.
  defp record_pushes(device_info, effects) do
    Enum.each(effects, fn
      {:push, event, payload} -> DeviceMessages.record(device_info, :sent, :device, event, payload)
      _effect -> :ok
    end)
  end

  defp device_info(socket), do: socket.assigns.session.device_info
end
