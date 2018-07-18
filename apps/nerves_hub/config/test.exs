use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub, NervesHubWeb.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :nerves_hub, firmware_upload: NervesHubCore.Firmwares.Upload.File

config :nerves_hub, NervesHub.Mailer,
  adapter: Bamboo.TestAdapter

config :nerves_hub, NervesHubCore.Firmwares.Upload.File,
  local_path: "/tmp/firmware",
  public_path: "/firmware"

config :nerves_hub, NervesHub.CertificateAuthority,
  host: "127.0.0.1",
  port: 8443,
  ssl: [
    keyfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/server-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/server.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]
