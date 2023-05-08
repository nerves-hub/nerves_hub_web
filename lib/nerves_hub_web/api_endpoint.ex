defmodule NervesHubWeb.API.Endpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub
  use SpandexPhoenix
  use Sentry.PlugCapture

  alias NervesHub.Config

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
    store: :cookie,
    key: "_nerves_hub_api_key",
    signing_salt: "WVt9MTK1"
  )

  plug(NervesHubWeb.APIRouter)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    vapor_config = Vapor.load!(Config)
    endpoint_config = vapor_config.api_endpoint

    config =
      Keyword.merge(config,
        secret_key_base: endpoint_config.secret_key_base,
        url: [
          host: endpoint_config.url_host,
          port: endpoint_config.url_port,
          scheme: endpoint_config.url_scheme
        ]
      )

    if config[:load_from_system_env] do
      port = System.get_env("API_PORT") || System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end
end
