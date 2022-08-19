defmodule NervesHubWWWWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub_www
  use SpandexPhoenix

  @session_options [
    store: :cookie,
    key: "_nerves_hub_key",
    signing_salt: "1CPjriVa"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  socket("/socket", NervesHubWWWWeb.UserSocket,
    websocket: [connect_info: [session: @session_options]]
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(
    Plug.Static,
    at: "/",
    from: :nerves_hub_www,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  file_upload_config =
    Application.get_env(:nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.File, [])

  if Keyword.get(file_upload_config, :enabled, false) do
    plug(
      Plug.Static,
      at: file_upload_config[:public_path],
      from: file_upload_config[:local_path]
    )
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
  plug(Plug.Logger)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    # 1GB
    length: 1_073_741_824,
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(
    Plug.Session,
    @session_options
  )

  plug(NervesHubWWWWeb.Router)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end
end
