use Mix.Config

config :beamware,
  device_serial_header: "x-client-dn",
  websocket_auth_methods: [:ssl, :header] # Options are :ssl or :header

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :beamware, BeamwareWeb.Endpoint,
  http: [port: 4002],
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4003,
    otp_app: :beamware,
    verify: :verify_peer, # Enable client SSL
    keyfile: Path.expand("./test/fixtures/certs/server-key.pem"),
    certfile: Path.expand("./test/fixtures/certs/server.pem"),
    cacertfile: Path.expand("./test/fixtures/certs/ca.pem")
  ]

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :beamware, Beamware.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  ssl: false,
  database: "beamware_test",
  pool: Ecto.Adapters.SQL.Sandbox
