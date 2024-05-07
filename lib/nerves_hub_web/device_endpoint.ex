defmodule NervesHubWeb.DeviceEndpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub
  use Sentry.PlugCapture

  socket(
    "/socket",
    NervesHubWeb.DeviceSocketCertAuth,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      drainer: [
        batch_size: 500,
        batch_interval: 1_000,
        shutdown: 30_000
      ]
    ]
  )

  plug(Sentry.PlugContext)

  plug(NervesHubWeb.Plugs.Logger)
end
