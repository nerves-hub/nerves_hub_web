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

  When the platform does not answer, the channel closes and the device joins it
  again; see `NervesHubWeb.Channels.Platform`. What the device said or was sent
  changes its session, so dropping it would leave the two out of step with
  nothing to bring them back. The join reads the device afresh. The socket, and
  the device's other channels, stay up.

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

  require Logger

  intercept(["updated", "deployment_updated"])

  # A device joins the bare "device" topic, which the serializers turn into
  # "device:<its own id>". Any other "device:..." topic passes through them as
  # sent, the socket routes every one of them here, and the channel is
  # subscribed to whichever topic was joined. So a join for any other id would
  # hand this device another device's broadcasts: its firmware URLs, support
  # scripts and local shell input.
  @decorate with_span("Channels.DeviceChannel.join")
  def join(topic, params, %{assigns: %{device_info: device_info}} = socket) do
    Logger.metadata(device_id: device_info.device_id, device_identifier: device_info.device_identifier)

    # Checked before the platform is asked, so a join to another device's topic
    # never reaches it.
    with :ok <- check_own_topic(topic, device_info),
         {:ok, session, effects} <-
           Platform.ask(socket, :device_join, fn -> DeviceLink.device_join(device_info, params) end) do
      socket =
        socket
        |> assign(:session, session)
        |> Effects.init()
        |> Effects.apply_all(effects)

      {:ok, socket}
    else
      {:error, :not_own_topic} ->
        Logger.warning("[DeviceChannel] refused a join to another device's topic #{inspect(topic)}")

        {:error, %{error: "unauthorized"}}

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

  defp advance(socket, function, fun) do
    case Platform.ask(socket, function, fn -> fun.(socket.assigns.session) end) do
      {session, effects} ->
        socket =
          socket
          |> assign(:session, session)
          |> Effects.apply_all(effects)

        {:noreply, socket}

      :unanswered ->
        rejoin(function)
    end
  end

  # Ends the channel so the device joins it again, which is what brings its
  # session back in step with whatever was lost.
  #
  # Phoenix tells the client `phx_error` when a channel exits, and clients rejoin
  # after that, with their own backoff. Returning `{:stop, {:shutdown, _},
  # socket}` would send `phx_close` instead, which NervesHubLink takes as the
  # channel ended for good, and it does not rejoin. Stopping with any other
  # reason sends `phx_error` too, but is logged as a crash, and `Platform.ask/3`
  # has already reported this -- for every device at once, when the platform is
  # slow. A `{:shutdown, _}` exit is not logged.
  @spec rejoin(atom()) :: no_return()
  defp rejoin(function), do: exit({:shutdown, {:unanswered, function}})

  # The topic is a string and `device_id` an integer, so this can't be a
  # pattern or a guard on `join/3`: neither can turn one into the other.
  defp check_own_topic(topic, device_info) do
    if topic == "device:#{device_info.device_id}", do: :ok, else: {:error, :not_own_topic}
  end
end
