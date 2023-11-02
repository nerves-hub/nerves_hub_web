defmodule NervesHubWeb.Endpoint do
  use Sentry.PlugCapture
  use Phoenix.Endpoint, otp_app: :nerves_hub

  @session_options [
    store: :cookie,
    key: "_nerves_hub_key",
    signing_salt: "1CPjriVa"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  socket("/socket", NervesHubWeb.UserSocket,
    websocket: [connect_info: [session: @session_options]]
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
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  firmware_upload = System.get_env("FIRMWARE_UPLOAD_BACKEND", "S3")

  if firmware_upload == "local" do
    plug(NervesHubWeb.Plugs.FileUpload)
  end

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

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(NervesHubWeb.Plugs.Logger)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    # 1GB
    length: 1_073_741_824,
    json_decoder: Jason
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

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  @impl Phoenix.Endpoint
  def init(_atom, config) do
    %{web_endpoint: endpoint} = NervesHub.Config.load!()

    {:ok,
     config
     |> update_in([:http], &Keyword.put(&1, :port, endpoint.http_port))
     |> Keyword.put(:url,
       host: endpoint.url_host,
       port: endpoint.url_port,
       scheme: endpoint.url_scheme
     )
     |> Keyword.put(:secret_key_base, endpoint.secret_key_base)
     |> Keyword.put(:live_view, signing_salt: endpoint.live_view_signing_salt)
     |> Keyword.put(:server, endpoint.server)}
  end
end
