defmodule NervesHubWeb.DeviceEndpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub
  use Sentry.PlugCapture

  # both `/socket` and `/device-socket` are supported for compatibility
  # with the web endpoint, where `/socket` is used by the `UserSocket`

  socket(
    "/socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      drainer: [
        batch_size: 500,
        batch_interval: 1_000,
        shutdown: 30_000
      ]
    ]
  )

  socket(
    "/device-socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      drainer: [
        batch_size: 500,
        batch_interval: 1_000,
        shutdown: 30_000
      ]
    ]
  )

  plug(NervesHubWeb.Plugs.ImAlive)

  plug(Sentry.PlugContext)

  plug(NervesHubWeb.Plugs.Logger)

  plug(NervesHubWeb.Plugs.DeviceEndpointRedirect)
end
