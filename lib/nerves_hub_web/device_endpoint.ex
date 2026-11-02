defmodule NervesHubWeb.DeviceEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  alias NervesHub.Helpers.WebsocketConnectionError

  # both `/socket` and `/device-socket` are supported for compatibility
  # with the web endpoint, where `/socket` is used by the `UserSocket`

  alias NervesHubWeb.Channels.DeviceJSONSerializer
  alias NervesHubWeb.Channels.DeviceMsgPackSerializer
  alias NervesHubWeb.Helpers.ServerName
  alias NervesHubWeb.Plugs.DeviceEndpointRedirect
  alias NervesHubWeb.Plugs.ImAlive

  socket(
    "/socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      compress: true,
      timeout: 180_000,
      fullsweep_after: 0,
      error_handler: {WebsocketConnectionError, :handle_error, []},
      serializer: [{DeviceMsgPackSerializer, "~> 3.0.0"}, {DeviceJSONSerializer, "~> 2.0.0"}]
    ],
    drainer: {NervesHubWeb.DeviceSocket, :drainer_configuration, []}
  )

  socket(
    "/device-socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      compress: true,
      timeout: 180_000,
      fullsweep_after: 0,
      error_handler: {WebsocketConnectionError, :handle_error, []},
      serializer: [{DeviceMsgPackSerializer, "~> 3.0.0"}, {DeviceJSONSerializer, "~> 2.0.0"}]
    ],
    drainer: {NervesHubWeb.DeviceSocket, :drainer_configuration, []}
  )

  plug(ImAlive)

  plug(Sentry.PlugContext)

  plug(DeviceEndpointRedirect)

  # Sockets are dispatched ahead of any plug here, so this can't be one.
  def call(conn, opts) do
    ServerName.record(conn)
    super(conn, opts)
  end
end
