import Config

# Start all of the applications
config :nerves_hub_www, app: "all"

web_port = 5000

config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warn

##
# NervesHub API
#
# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub_www, NervesHubWeb.API.Endpoint,
  http: [port: 4002],
  server: false

##
# NervesHub Device
#
config :nerves_hub_www, NervesHubWeb.DeviceEndpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4101,
    otp_app: :nerves_hub_www,
    # Enable client SSL
    verify: :verify_peer,
    verify_fun: {&NervesHubDevice.SSL.verify_fun/3, nil},
    fail_if_no_peer_cert: true,
    keyfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org-key.pem"]),
    certfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org.pem"]),
    cacertfile: Path.join([__DIR__, "../test/fixtures/ssl/ca.pem"])
  ]

##
# NervesHub
#
config :nerves_hub_www,
  allow_signups?: true,
  firmware_upload: NervesHub.UploadMock,
  port: web_port

config :nerves_hub_www,
  delta_updater: NervesHub.DeltaUpdaterMock

config :nerves_hub_www, NervesHub.Firmwares.Upload.S3, bucket: "mybucket"

config :nerves_hub_www, NervesHub.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub_www, NervesHub.Repo,
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub_www, NervesHub.CertificateAuthority,
  host: "127.0.0.1",
  port: 8443,
  ssl: [
    keyfile: Path.join([__DIR__, "../test/fixtures/ssl/ca-client-key.pem"]),
    certfile: Path.join([__DIR__, "../test/fixtures/ssl/ca-client.pem"]),
    cacertfile: Path.join([__DIR__, "../test/fixtures/ssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]

config :nerves_hub_www, NervesHub.Mailer, adapter: Bamboo.TestAdapter

config :nerves_hub_www, Oban, queues: false, plugins: false

##
# NervesHubWWW
#
config :nerves_hub_www, NervesHubWeb.Endpoint,
  http: [port: web_port],
  server: false,
  secret_key_base: "x7Vj9rmmRke//ctlapsPNGHXCRTnArTPbfsv6qX4PChFT9ARiNR5Ua8zoRilNCmX",
  live_view: [signing_salt: "FnV9rP_c2BL11dvh"]
