defmodule NervesHubWeb.DeviceEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  alias NervesHub.Helpers.WebsocketConnectionError

  # both `/socket` and `/device-socket` are supported for compatibility
  # with the web endpoint, where `/socket` is used by the `UserSocket`

  socket(
    "/socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      compress: true,
      timeout: 180_000,
      fullsweep_after: 0,
      error_handler: {WebsocketConnectionError, :handle_error, []}
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
      error_handler: {WebsocketConnectionError, :handle_error, []}
    ],
    drainer: {NervesHubWeb.DeviceSocket, :drainer_configuration, []}
  )

  plug(NervesHubWeb.Plugs.ImAlive)

  plug(Sentry.PlugContext)

  plug(NervesHubWeb.Plugs.DeviceEndpointRedirect)
end
