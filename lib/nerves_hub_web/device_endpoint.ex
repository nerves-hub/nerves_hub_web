defmodule NervesHubWeb.DeviceEndpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub
  use Sentry.PlugCapture

  socket(
    "/socket",
    NervesHubWeb.DeviceSocketCertAuth,
    drainer: [
      batch_size: 500,
      batch_interval: 1_000,
      shutdown: 30_000
    ],
    websocket: [
      connect_info: [:peer_data, :x_headers]
    ]
  )

  plug(Sentry.PlugContext)

  plug(NervesHubWeb.Plugs.Logger)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok, config}
  end
end
