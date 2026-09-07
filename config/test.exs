import Config

alias NervesHub.DeviceLink.Dispatcher
alias NervesHub.DeviceLink.Dispatcher.Remote
alias NervesHub.DeviceLink.PeerVerification
alias NervesHub.Firmwares.Upload.S3
alias Swoosh.Adapters.Test

config :bcrypt_elixir, log_rounds: 4

# Print only warnings and errors during test
config :logger, level: :warning

config :nerves_hub, NervesHub.AnalyticsRepo,
  url: System.get_env("CLICKHOUSE_URL", "http://default:@localhost:8123/default_test")

config :nerves_hub, NervesHub.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub, NervesHub.RateLimit, limit: 100

config :nerves_hub, NervesHub.Repo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/nerves_hub_test"),
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: if(System.get_env("CI"), do: 10, else: System.schedulers_online() * 2),
  queue_target: 2000

config :nerves_hub, NervesHub.SwooshMailer, adapter: Test
config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File
config :nerves_hub, NervesHub.Uploads.File, local_path: System.tmp_dir(), public_path: "/uploads"

# Both endpoints listen for real during tests, so two checkouts running their
# suites at once collide on the port and the second fails to boot with
# `:eaddrinuse` — which reads as a broken application rather than a busy port.
# Worktrees make that a normal thing to do rather than an accident.
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  code_reloader: false,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: String.to_integer(System.get_env("DEVICE_ENDPOINT_TEST_PORT", "4101")),
    otp_app: :nerves_hub,
    thousand_island_options: [
      transport_options: [
        # Enable client SSL
        verify: :verify_peer,
        verify_fun: {&PeerVerification.verify_fun/3, nil},
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

# See the note on DeviceEndpoint below: both endpoints listen during tests, so
# both need a way out of a port collision between concurrent checkouts.
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("WEB_ENDPOINT_TEST_PORT", "4100"))],
  server: true,
  secret_key_base: "x7Vj9rmmRke//ctlapsPNGHXCRTnArTPbfsv6qX4PChFT9ARiNR5Ua8zoRilNCmX",
  live_view: [signing_salt: "FnV9rP_c2BL11dvh"],
  url: [
    host: "localhost",
    scheme: "http",
    port: 1234
  ]

config :nerves_hub, Oban, testing: :manual
config :nerves_hub, S3, bucket: "mybucket"
# Short enough that analytics writes land within an `assert_eventually`.
config :nerves_hub, :analytics_buffer, max_delay: to_timeout(millisecond: 50)
config :nerves_hub, :firmware_download_options, plug: {Req.Test, NervesHub}
config :nerves_hub, analytics_enabled: true
config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, :test_warnings, missing_form_id: :raise

config :phoenix_test, :endpoint, NervesHubWeb.Endpoint

config :sentry, environment_name: :test

# Run the suite against remote dispatch to check that a caller without the
# platform stack gets the same behaviour as one with it:
#
#     DEVICE_LINK_DISPATCH=remote mix test
#
# Calls go to this node over :erpc, so the wire format is exercised for real
# while the database stays where the sandbox can see it.
if System.get_env("DEVICE_LINK_DISPATCH") == "remote" do
  config :nerves_hub, Dispatcher, Remote
end
