defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket
  use OpenTelemetryDecorator

  require Logger

  alias NervesHub.DeviceLink.Connections

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)
  channel("extensions", NervesHubWeb.ExtensionsChannel)

  defoverridable init: 1, handle_in: 2, terminate: 2

  @impl Phoenix.Socket.Transport
  @decorate with_span("Channels.DeviceSocket.terminate")
  def terminate(reason, {_channels_info, socket} = state) do
    %{assigns: %{device: device, reference_id: reference_id}} = socket
    Connections.disconnect_device(reason, device, reference_id)
    super(reason, state)
  end

  @impl Phoenix.Socket.Transport
  def handle_in({payload, opts} = msg, {state, socket}) do
    message = socket.serializer.decode!(payload, opts)

    socket = heartbeat(message, socket)

    super(msg, {state, socket})
  end

  @decorate with_span("Channels.DeviceSocket.heartbeat")
  defp heartbeat(%Phoenix.Socket.Message{topic: "phoenix", event: "heartbeat"}, socket) do
    if heartbeat?(socket) do
      Connections.device_heartbeat(socket.assigns.reference_id)

      last_heartbeat =
        DateTime.utc_now()
        |> DateTime.truncate(:second)

      assign(socket, :last_heartbeat_at, last_heartbeat)
    else
      socket
    end
  end

  defp heartbeat(_message, socket), do: socket

  defp heartbeat?(%{assigns: %{last_heartbeat_at: last_heartbeat_at}}) do
    mins_ago = DateTime.diff(DateTime.utc_now(), last_heartbeat_at, :minute)

    mins_ago >= last_seen_update_interval()
  end

  defp heartbeat?(_), do: true

  # Used by Devices connecting with SSL certificates
  @impl Phoenix.Socket
  @decorate with_span("Channels.DeviceSocket.connect#ssl_cert")
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}})
      when not is_nil(ssl_cert) do
    case Connections.connect_device({:ssl_certs, ssl_cert}) do
      {:ok, ref_and_device} ->
        socket_and_assigns(socket, ref_and_device)

      error ->
        error
    end
  end

  # Used by Devices connecting with HMAC Shared Secrets
  @impl Phoenix.Socket
  @decorate with_span("Channels.DeviceSocket.connect#shared_secrets")
  def connect(_params, socket, %{x_headers: x_headers})
      when is_list(x_headers) and length(x_headers) > 0 do
    case Connections.connect_device({:shared_secrets, x_headers}) do
      {:ok, ref_and_device} ->
        socket_and_assigns(socket, ref_and_device)

      error ->
        error
    end
  end

  @impl Phoenix.Socket
  def connect(_params, _socket, _connect_info) do
    {:error, :no_auth}
  end

  @impl Phoenix.Socket
  def id(%{assigns: %{device: device}}), do: "device_socket:#{device.id}"
  def id(_socket), do: nil

  def drainer_configuration() do
    config = Application.get_env(:nerves_hub, :device_socket_drainer)

    [
      batch_size: config[:batch_size],
      batch_interval: config[:batch_interval],
      shutdown: config[:shutdown]
    ]
  end

  defp socket_and_assigns(socket, {ref_id, device}) do
    socket =
      socket
      |> assign(:device, device)
      |> assign(:reference_id, ref_id)

    {:ok, socket}
  end

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect(exit_reason, socket)

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect({:error, reason}, %{
         assigns: %{
           device: device,
           reference_id: reference_id
         }
       }) do
    if reason == {:shutdown, :disconnected} do
      :telemetry.execute([:nerves_hub, :devices, :duplicate_connection], %{count: 1}, %{
        ref_id: reference_id,
        device: device
      })
    end

    shutdown(device, reference_id)

    :ok
  end

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect(_, %{
         assigns: %{
           device: device,
           reference_id: reference_id
         }
       }) do
    shutdown(device, reference_id)
  end

  @decorate with_span("Channels.DeviceSocket.shutdown")
  defp shutdown(device, reference_id) do
    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1}, %{
      ref_id: reference_id,
      identifier: device.identifier
    })

    :ok = Connections.device_disconnected(reference_id)

    Tracker.offline(device)

    :ok
  end

  defp last_seen_update_interval() do
    Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes)
  end
end
