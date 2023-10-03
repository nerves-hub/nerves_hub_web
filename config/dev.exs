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
  watchers: [],
  https: [
    ip: {0, 0, 0, 0},
    port: 4001,
    otp_app: :nerves_hub,
    # Enable client SSL
    # Older versions of OTP 25 may break using using devices
    # that support TLS 1.3 or 1.2 negotiation. To mitigate that
    # potential error, we enforce TLS 1.2. If you're using OTP >= 25.1
    # on all devices, then it is safe to allow TLS 1.3 by removing
    # the versions constraint and setting `certificate_authorities: false`
    # See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
    #
    # certificate_authorities: false,
    versions: [:"tlsv1.2"],
    verify: :verify_peer,
    verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
    fail_if_no_peer_cert: true,
    keyfile: Path.join(ssl_dir, "device.nerves-hub.org-key.pem"),
    certfile: Path.join(ssl_dir, "device.nerves-hub.org.pem"),
    cacertfile: Path.join(ssl_dir, "ca.pem")
  ]

##
# NervesHub
#
config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  enabled: true,
  local_path: Path.expand("tmp/firmware"),
  public_path: "/firmware"

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
