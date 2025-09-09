import Config

config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warning

config :nerves_hub, NervesHub.AnalyticsRepo,
  url: System.get_env("CLICKHOUSE_URL", "http://default:@localhost:8123/default_test")

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: "mybucket"

config :nerves_hub, NervesHub.ObanRepo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_test"),
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :nerves_hub, NervesHub.RateLimit, limit: 100

config :nerves_hub, NervesHub.Repo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_test"),
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  queue_target: 2000

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Test
config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File
config :nerves_hub, NervesHub.Uploads.File, local_path: System.tmp_dir(), public_path: "/uploads"

config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  code_reloader: false,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4101,
    otp_app: :nerves_hub,
    thousand_island_options: [
      transport_options: [
        # Enable client SSL
        verify: :verify_peer,
        verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
        fail_if_no_peer_cert: true,
        keyfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org-key.pem"]),
        certfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org.pem"]),
        cacertfile: Path.join([__DIR__, "../test/fixtures/ssl/ca.pem"])
      ]
    ]
  ]

config :nerves_hub, NervesHubWeb.DeviceSocket,
  shared_secrets: [
    enabled: true
  ]

config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: 4100],
  server: true,
  secret_key_base: "x7Vj9rmmRke//ctlapsPNGHXCRTnArTPbfsv6qX4PChFT9ARiNR5Ua8zoRilNCmX",
  live_view: [signing_salt: "FnV9rP_c2BL11dvh"],
  url: [
    host: "localhost",
    scheme: "http",
    port: 1234
  ]

config :nerves_hub, Oban, testing: :manual
config :nerves_hub, analytics_enabled: true
config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_test, :endpoint, NervesHubWeb.Endpoint

config :sentry, environment_name: :test
