defmodule NervesHubWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  alias NervesHub.Helpers.WebsocketConnectionError

  def fetch_signing_salt() do
    Application.get_env(:nerves_hub, __MODULE__)[:live_view][:signing_salt]
  end

  @session_options [
    store: :cookie,
    key: "_nerves_hub_key",
    signing_salt: {__MODULE__, :fetch_signing_salt, []}
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  socket("/socket", NervesHubWeb.UserSocket, websocket: [connect_info: [session: @session_options]])

  socket("/events-socket", NervesHubWeb.EventStreamSocket, websocket: true)

  socket(
    "/device-socket",
    NervesHubWeb.DeviceSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers],
      compress: true,
      timeout: 180_000,
      fullsweep_after: 0,
      error_handler: {WebsocketConnectionError, :handle_error, []},
      serializer: [{NervesHubWeb.Channels.DeviceJSONSerializer, "~> 2.0.0"}]
    ]
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(
    Plug.Static,
    at: "/",
    from: :nerves_hub,
    gzip: false,
    only: ~w(assets css fonts images js favicon.ico robots.txt geo)
  )

  plug(NervesHubWeb.Plugs.ConfigureUploads)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket(
      "/phoenix/live_reload/socket",
      Phoenix.LiveReloader.Socket,
      websocket: true
    )

    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(NervesHubWeb.Plugs.ImAlive)

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, NervesHubWeb.DynamicConfigMultipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Sentry.PlugContext)

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(
    Plug.Session,
    @session_options
  )

  plug(NervesHubWeb.Router)
end
