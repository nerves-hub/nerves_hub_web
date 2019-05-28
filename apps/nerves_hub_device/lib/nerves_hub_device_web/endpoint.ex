defmodule NervesHubDeviceWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :nerves_hub_device

  socket(
    "/socket",
    NervesHubDeviceWeb.UserSocket,
    websocket: [
      connect_info: [:peer_data, :x_headers]
    ]
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug(
    Plug.Static,
    at: "/",
    from: :nerves_hub_device,
    gzip: false,
    only: ~w(css fonts images js favicon.ico robots.txt)
  )

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 160_000_000,
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug(
    Plug.Session,
    store: :cookie,
    key: "_nerves_hub_key",
    signing_salt: "1CPjriVa"
  )

  plug(NervesHubDeviceWeb.Router)

  @doc """
  Callback invoked for dynamically configuring the endpoint.

  It receives the endpoint configuration and checks if
  configuration should be loaded from the system environment.
  """
  def init(_key, config) do
    config = verify_fun(config)

    if config[:load_from_system_env] do
      port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end

  defp verify_fun(config) do
    if https_opts = Keyword.get(config, :https) do
      https_opts = Keyword.put(https_opts, :verify_fun, {&NervesHubDevice.SSL.verify_fun/3, nil})
      Keyword.put(config, :https, https_opts)
    else
      config
    end
  end
end
