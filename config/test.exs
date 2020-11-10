import Config

web_port = 5000

config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warn

##
# NervesHub API
#
# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  http: [port: 4002],
  server: false

##
# NervesHub Device
#
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4101,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    verify_fun: {&NervesHubDevice.SSL.verify_fun/3, nil},
    fail_if_no_peer_cert: true,
    keyfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org-key.pem"]),
    certfile: Path.join([__DIR__, "../test/fixtures/ssl/device.nerves-hub.org.pem"]),
    cacertfile: Path.join([__DIR__, "../test/fixtures/ssl/ca.pem"])
  ]

##
# NervesHubWebCore
#
config :nerves_hub_web_core,
  firmware_upload: NervesHubWebCore.UploadMock,
  port: web_port

config :nerves_hub_web_core,
  delta_updater: NervesHubWebCore.DeltaUpdaterMock

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3, bucket: "mybucket"

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub_web_core, NervesHubWebCore.Repo,
  ssl: false,
  pool_size: 30,
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: "127.0.0.1",
  port: 8443,
  ssl: [
    keyfile: Path.join([__DIR__, "../test/fixtures/ssl/ca-client-key.pem"]),
    certfile: Path.join([__DIR__, "../test/fixtures/ssl/ca-client.pem"]),
    cacertfile: Path.join([__DIR__, "../test/fixtures/ssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]

config :nerves_hub_web_core, NervesHubWebCore.Mailer, adapter: Bamboo.TestAdapter

config :nerves_hub_web_core, Oban, queues: false, plugins: false

##
# NervesHubWWW
#
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  http: [port: web_port],
  server: false
