use Mix.Config

config :nerves_hub,
  device_serial_header: "x-client-dn",
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl, :header]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: 4002],
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4003,
    otp_app: :nerves_hub,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: Path.expand("./test/fixtures/cfssl/server-key.pem"),
    certfile: Path.expand("./test/fixtures/cfssl/server.pem"),
    cacertfile: Path.expand("./test/fixtures/cfssl/ca.pem")
  ]

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :nerves_hub, NervesHub.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_URL"),
  ssl: false,
  database: "nerves_hub_test",
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  local_path: "/tmp/firmware",
  public_path: "/firmware"

config :nerves_hub, NervesHub.CertificateAuthority,
  host: "127.0.0.1",
  port: 8443,
  ssl: [
    keyfile: Path.expand("./test/fixtures/cfssl/server-key.pem"),
    certfile: Path.expand("./test/fixtures/cfssl/server.pem"),
    cacertfile: Path.expand("./test/fixtures/cfssl/ca.pem"),
    server_name_indication: 'ca.nerves-hub.org'
  ]
