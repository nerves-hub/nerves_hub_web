import Config

# Start all of the applications
config :nerves_hub, app: "all"

config :nerves_hub, deploy_env: "dev"

ssl_dir =
  (System.get_env("NERVES_HUB_CA_DIR") || Path.join([__DIR__, "../test/fixtures/ssl/"]))
  |> Path.expand()

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  debug_errors: true,
  code_reloader: false,
  check_origin: false,
  watchers: []

##
# NervesHub
#
config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  enabled: true,
  local_path: Path.expand("tmp/firmware"),
  public_path: "/firmware"

config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File

config :nerves_hub, NervesHub.Uploads.File,
  enabled: true,
  local_path: Path.expand("tmp/uploads"),
  public_path: "/uploads"

# config :nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: System.get_env("S3_BUCKET_NAME")

config :nerves_hub, NervesHub.Repo, ssl: false

config :nerves_hub, NervesHub.ObanRepo, ssl: false

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Local

config :nerves_hub, NervesHub.RateLimit, limit: 10

##
# NervesHubWWW
#
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [npm: ["run", "watch", cd: Path.expand("../assets", __DIR__)]]

config :nerves_hub, NervesHubWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/nerves_hub_www_web/views/.*(ex)$},
      ~r{lib/nerves_hub_www_web/templates/.*(eex|md)$},
      ~r{lib/nerves_hube_www_web/live/.*(ex)$}
    ]
  ]

if System.get_env("OTEL_ENABLED", "false") == "true" do
  # Export to a local collector
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: "http://localhost:4318"
else
  config :opentelemetry, tracer: :otel_tracer_noop, traces_exporter: :none
end

config :sentry, environment_name: "developent"
