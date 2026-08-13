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

  alias NervesHub.DeviceLink
  alias NervesHubWeb.Channels.Effects

  intercept(["updated", "deployment_updated"])

  @decorate with_span("Channels.DeviceChannel.join")
  def join("device:" <> _device_id, params, %{assigns: %{device_info: device_info}} = socket) do
    Logger.metadata(device_id: device_info.device_id, device_identifier: device_info.device_identifier)

    case DeviceLink.device_join(device_info, params) do
      {:ok, session, effects} ->
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
    advance(socket, &DeviceLink.device_message(&1, event, payload))
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_info")
  def handle_info(message, socket) do
    advance(socket, &DeviceLink.device_notify(&1, message))
  end

  @impl Phoenix.Channel
  @decorate with_span("Channels.DeviceChannel.handle_out")
  def handle_out(event, payload, socket) do
    advance(socket, &DeviceLink.device_broadcast(&1, event, payload))
  end

  defp advance(socket, fun) do
    {session, effects} = fun.(socket.assigns.session)

    socket =
      socket
      |> assign(:session, session)
      |> Effects.apply_all(effects)

    {:noreply, socket}
  end
end
