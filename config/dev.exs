import Config

ssl_dir =
  (System.get_env("NERVES_HUB_CA_DIR") || Path.join([__DIR__, "../test/fixtures/ssl/"]))
  |> Path.expand()

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20

##
# NervesHub Web
#
config :nerves_hub, NervesHubWeb.Endpoint,
  url: [
    host: System.get_env("WEB_HOST", "localhost"),
    scheme: System.get_env("WEB_SCHEME", "http"),
    port: String.to_integer(System.get_env("WEB_PORT", "4000"))
  ],
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [npm: ["run", "watch", cd: Path.expand("../assets", __DIR__)]],
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/nerves_hub_web/views/.*(ex)$},
      ~r{lib/nerves_hub_web/templates/.*(eex|md)$},
      ~r{lib/nerves_hub_web/live/.*(ex)$}
    ]
  ]

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
    thousand_island_options: [
      transport_module: NervesHub.DeviceSSLTransport,
      transport_options: [
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
    ]
  ]

##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_dev"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  ssl: false

config :nerves_hub, NervesHub.ObanRepo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_dev"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  ssl: false

##
# Firmware upload
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

##
# Other
#
config :nerves_hub, NervesHubWeb.DeviceSocket,
  shared_secrets: [
    enabled: true
  ]

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Local

config :nerves_hub, NervesHub.RateLimit, limit: 10

config :nerves_hub,
  open_for_registrations: true
