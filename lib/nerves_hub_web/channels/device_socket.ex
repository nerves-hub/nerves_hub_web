defmodule NervesHubWeb.DeviceSocket do
  use Phoenix.Socket
  use OpenTelemetryDecorator

  alias NervesHub.DeviceLink.Client, as: DeviceLink
  alias NervesHubWeb.Helpers.ClientIP
  alias Phoenix.Socket.Transport

  channel("console", NervesHubWeb.ConsoleChannel)
  channel("device:*", NervesHubWeb.DeviceChannel)
  channel("extensions", NervesHubWeb.ExtensionsChannel)

  defoverridable init: 1, handle_in: 2, terminate: 2

  @impl Transport
  def init(state_tuple) do
    {:ok, {state, socket}} = super(state_tuple)
    socket = on_connect(socket)
    {:ok, {state, socket}}
  end

  @impl Transport
  @decorate with_span("Channels.DeviceSocket.terminate")
  def terminate(reason, {channels_info, socket}) do
    socket = on_disconnect(reason, socket)
    super(reason, {channels_info, socket})
  end

  @impl Transport
  def handle_in(msg, {state, socket}) do
    socket = heartbeat(socket)
    super(msg, {state, socket})
  end

  @decorate with_span("Channels.DeviceSocket.heartbeat")
  defp heartbeat(%{assigns: %{device_info: device_info}} = socket) do
    if update_heartbeat?(socket) do
      _ = DeviceLink.heartbeat(device_info.connection_ref)
      update_last_heartbeat(socket)
    else
      socket
    end
  end

  defp heartbeat(socket), do: socket

  defp update_heartbeat?(%{assigns: %{last_heartbeat: last_heartbeat}}) do
    seconds_ago = System.monotonic_time(:second) - last_heartbeat

    seconds_ago >= last_seen_update_interval()
  end

  defp update_heartbeat?(_), do: false

  defp update_last_heartbeat(socket) do
    assign(socket, :last_heartbeat, System.monotonic_time(:second))
  end

  # Used by Devices connecting with SSL certificates
  @impl Phoenix.Socket
  @decorate with_span("Channels.DeviceSocket.connect:cert_auth")
  def connect(_params, socket, %{peer_data: %{ssl_cert: ssl_cert}} = connect_info) when not is_nil(ssl_cert) do
    authenticate(socket, {:ssl_cert, ssl_cert}, connect_info)
  end

  # Used by Devices connecting with HMAC Shared Secrets
  @decorate with_span("Channels.DeviceSocket.connect:shared_secrets")
  def connect(_params, socket, %{x_headers: x_headers} = connect_info) when is_list(x_headers) and x_headers != [] do
    authenticate(socket, {:shared_secret, Map.new(x_headers)}, connect_info)
  end

  def connect(_params, _socket, _connect_info) do
    {:error, :no_auth}
  end

  @impl Phoenix.Socket
  def id(%{assigns: %{device_info: device_info}}), do: "device_socket:#{device_info.device_id}"
  def id(_socket), do: nil

  def drainer_configuration() do
    config = Application.get_env(:nerves_hub, :device_socket_drainer)

    [
      batch_size: config[:batch_size],
      batch_interval: config[:batch_interval],
      shutdown: config[:shutdown]
    ]
  end

  # A device cannot be admitted without the platform's say-so, and the platform
  # may be unreachable -- during a deploy, a partition, or before this node has
  # finished joining the cluster. Refusing is correct; raising is not, because it
  # answers the device with a 500 and buries the reason in a rendered error page.
  defp authenticate(socket, credentials, connect_info) do
    case DeviceLink.authenticate(credentials) do
      {:ok, device_info} -> socket_and_assigns(socket, device_info, ip_address(socket, connect_info))
      {:error, reason} -> {:error, reason}
    end
  catch
    kind, reason ->
      :telemetry.execute([:nerves_hub, :devices, :platform_unavailable], %{count: 1}, %{
        kind: kind,
        reason: reason
      })

      {:error, :platform_unavailable}
  end

  defp socket_and_assigns(socket, device_info, ip_address) do
    # disconnect devices using the same identifier
    _ = socket.endpoint.broadcast_from(self(), "device_socket:#{device_info.device_id}", "disconnect", %{})

    socket =
      socket
      |> assign(:device_info, device_info)
      |> assign(:ip_address, ip_address)

    {:ok, socket}
  end

  # The address the device reached us from. How that is established differs
  # between the two endpoints serving devices, so the endpoint reached decides
  # which header, if any, may be believed -- see `NervesHubWeb.Helpers.ClientIP`.
  defp ip_address(socket, connect_info) do
    config = Application.get_env(:nerves_hub, socket.endpoint, [])

    ClientIP.resolve(
      connect_info,
      Keyword.get(config, :forwarded_ip_header),
      Keyword.get(config, :forwarded_ip_trailing_hops, 0)
    )
  end

  @decorate with_span("Channels.DeviceSocket.on_connect")
  defp on_connect(%{assigns: %{device_info: device_info}} = socket) do
    # Report connection and use connection id as reference
    {:ok, device_info} = DeviceLink.connect(device_info, socket.assigns[:ip_address])

    :telemetry.execute([:nerves_hub, :devices, :connect], %{count: 1}, %{
      ref_id: device_info.connection_ref,
      identifier: device_info.device_identifier,
      firmware_uuid: get_in(device_info, [Access.key(:firmware_metadata), Access.key(:uuid)])
    })

    # this is required by `DeviceJSONSerializer` which needs to update the message topic,
    # allowing for the socket to map messages correctly
    #
    # we could remove this and instead modify the payload in `handle_in`, but I favoured
    # this approach as it simplifies the logic in `handle_in` and keeps the topic remapping
    # logic in one place, the serializer
    Process.put(:device_id, device_info.device_id)

    socket
    |> assign(:device_info, device_info)
    |> update_last_heartbeat()
  end

  defp on_disconnect(_reason, %{assigns: %{disconnection_handled?: true} = socket}) do
    socket
  end

  @decorate with_span("Channels.DeviceSocket.on_disconnect")
  defp on_disconnect(reason, socket) do
    %{assigns: %{device_info: device_info}} = socket

    if reason == {:error, {:shutdown, :disconnected}} do
      :telemetry.execute([:nerves_hub, :devices, :duplicate_connection], %{count: 1}, %{
        ref_id: device_info.connection_ref,
        device_id: device_info.device_id,
        device_identifier: device_info.device_identifier
      })
    end

    :telemetry.execute([:nerves_hub, :devices, :disconnect], %{count: 1}, %{
      ref_id: device_info.connection_ref,
      device_id: device_info.device_id,
      device_identifier: device_info.device_identifier
    })

    # its possible that this is a stale connection and the device has already reconnected,
    # which means the following call might return :error, but we can ignore it
    _ = DeviceLink.disconnect(device_info.connection_ref)

    assign(socket, :disconnection_handled?, true)
  end

  defp last_seen_update_interval() do
    interval = Application.get_env(:nerves_hub, :device_last_seen_update_interval_minutes) * 60

    jitter = Application.get_env(:nerves_hub, :device_last_seen_update_interval_jitter_seconds)

    interval + Enum.random(-jitter..jitter)
  end
end
