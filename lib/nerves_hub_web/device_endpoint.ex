defmodule NervesHubWeb.DeviceEndpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  socket(
    "/socket",
    NervesHubWeb.DeviceSocket,
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
  def init(_atom, config) do
    %{device_endpoint: endpoint} = NervesHub.Config.load!()

    {:ok,
     config
     |> update_in(
       [:https],
       &Keyword.merge(&1,
         port: endpoint.https_port,
         keyfile: endpoint.https_keyfile,
         certfile: endpoint.https_certfile,
         cacertfile: endpoint.https_cacertfile
       )
     )
     |> Keyword.put(:url, host: endpoint.url_host, port: endpoint.url_port, scheme: "https")
     |> Keyword.put(:secret_key_base, endpoint.secret_key_base)
     |> Keyword.put(:live_view, signing_salt: endpoint.live_view_signing_salt)
     |> Keyword.put(:server, endpoint.server)}
  end
end
