defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket
  use OpenTelemetryDecorator

  require Logger

  alias NervesHub.Devices
  alias NervesHub.Devices.Connections
  alias NervesHub.Devices.DeviceConnection
  alias NervesHub.Tracker

  alias NervesHub.RPC.DeviceAuth

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device", NervesHubWeb.DeviceChannel)
  channel("extensions", NervesHubWeb.ExtensionsChannel)

  defoverridable init: 1, handle_in: 2, terminate: 2

  @impl Phoenix.Socket.Transport
  def init(state_tuple) do
    {:ok, {state, socket}} = super(state_tuple)
    socket = on_connect(socket)
    {:ok, {state, socket}}
  end

  @impl Phoenix.Socket.Transport
  @decorate with_span("Channels.DeviceSocket.terminate")
  def terminate(reason, {_channels_info, socket} = state) do
    on_disconnect(reason, socket)
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
  @decorate with_span("Channels.DeviceSocket.connect")
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}})
      when not is_nil(ssl_cert) do
    X509.Certificate.from_der!(ssl_cert)
    |> Devices.get_device_by_x509()
    |> case do
      {:ok, device} ->
        socket_and_assigns(socket, device)

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :cert,
          reason: error
        })

        {:error, :invalid_auth}
    end
  end

  # Used by Devices connecting with HMAC Shared Secrets
  @decorate with_span("Channels.DeviceSocket.connect")
  def connect(_params, socket, %{x_headers: x_headers})
      when is_list(x_headers) and length(x_headers) > 0 do
    headers = Map.new(x_headers)

    case DeviceAuth.connect_device({:shared_secrets, x_headers}) do
      {:ok, device} ->
        socket_and_assigns(socket, Devices.preload_product(device))

      error ->
        :telemetry.execute([:nerves_hub, :devices, :invalid_auth], %{count: 1}, %{
          auth: :shared_secrets,
          reason: error,
          product_key: Map.get(headers, "x-nh-key", "*empty*")
        })

        {:error, :invalid_auth}
    end
  end

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

  defp socket_and_assigns(socket, device) do
    # disconnect devices using the same identifier
    _ = socket.endpoint.broadcast_from(self(), "device_socket:#{device.id}", "disconnect", %{})

    socket =
      socket
      |> assign(:device, device)

    {:ok, socket}
  end

  @decorate with_span("Channels.DeviceSocket.on_connect#registered")
  defp on_connect(%{assigns: %{device: %{status: :registered} = device}} = socket) do
    socket
    |> assign(device: Devices.set_as_provisioned!(device))
    |> on_connect()
  end

  @decorate with_span("Channels.DeviceSocket.on_connect#provisioned")
  defp on_connect(%{assigns: %{device: device}} = socket) do
    # Report connection and use connection id as reference
    {:ok, %DeviceConnection{id: connection_id}} =
      Connections.device_connected(device.id)

    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: connection_id,
      identifier: socket.assigns.device.identifier,
      firmware_uuid:
        get_in(socket.assigns.device, [Access.key(:firmware_metadata), Access.key(:uuid)])
    })

    Tracker.online(device)

    socket
    |> assign(:device, device)
    |> assign(:reference_id, connection_id)
  end

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect(exit_reason, socket)

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
