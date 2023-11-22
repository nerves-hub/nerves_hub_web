import Config

# Start all of the applications
config :nerves_hub, app: "all"

config :nerves_hub, deploy_env: "test"

web_port = 5000

config :bcrypt_elixir, log_rounds: 4

config :logger, :default_handler, false

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: []

##
# NervesHub
#
config :nerves_hub,
  firmware_upload: NervesHub.UploadMock,
  port: web_port

config :nerves_hub,
  delta_updater: NervesHub.DeltaUpdaterMock

config :nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: "mybucket"

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File

config :nerves_hub, NervesHub.Uploads.File,
  local_path: System.tmp_dir(),
  public_path: "/uploads"

config :nerves_hub, NervesHub.Repo,
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub, NervesHub.ObanRepo,
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Test

config :nerves_hub, Oban, queues: false, plugins: false

config :nerves_hub, NervesHub.RateLimit, limit: 100

##
# NervesHubWWW
#
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: web_port],
  server: false,
  secret_key_base: "x7Vj9rmmRke//ctlapsPNGHXCRTnArTPbfsv6qX4PChFT9ARiNR5Ua8zoRilNCmX",
  live_view: [signing_salt: "FnV9rP_c2BL11dvh"]

# OTel
config :opentelemetry, tracer: :otel_tracer_noop, traces_exporter: :none

config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:otel_exporter_tab, []}
  }

config :sentry,
  environment_name: :test,
  included_environments: []
