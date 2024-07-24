import Config

config :bcrypt_elixir, log_rounds: 4

config :logger, :default_handler, false

##
# NervesHub Web
#
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: 4100],
  server: true,
  secret_key_base: "x7Vj9rmmRke//ctlapsPNGHXCRTnArTPbfsv6qX4PChFT9ARiNR5Ua8zoRilNCmX",
  live_view: [signing_salt: "FnV9rP_c2BL11dvh"]

##
# NervesHub Device
#
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

##
# Firmware uploader
#
config :nerves_hub, firmware_upload: NervesHub.UploadMock

config :nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: "mybucket"

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File

config :nerves_hub, NervesHub.Uploads.File,
  local_path: System.tmp_dir(),
  public_path: "/uploads"

##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_test"),
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :nerves_hub, NervesHub.ObanRepo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_test"),
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :nerves_hub, Oban, testing: :manual

##
# Other
#
config :nerves_hub, NervesHubWeb.DeviceSocket,
  shared_secrets: [
    enabled: true
  ]

config :nerves_hub, delta_updater: NervesHub.DeltaUpdaterMock

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Test

config :nerves_hub, NervesHub.RateLimit, limit: 100

config :sentry, environment_name: :test

config :phoenix_test, :endpoint, NervesHubWeb.Endpoint

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
