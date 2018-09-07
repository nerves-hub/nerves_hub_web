use Mix.Config

config :bcrypt_elixir,
  log_rounds: 4

config :nerves_hub_core, firmware_upload: NervesHubCore.Firmwares.Upload.File

config :nerves_hub_core, NervesHubCore.Firmwares.Upload.File,
  local_path: System.tmp_dir(),
  public_path: "/firmware"

config :nerves_hub_core, NervesHubCore.Repo,
  adapter: Ecto.Adapters.Postgres,
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub_core, NervesHubCore.CertificateAuthority,
  host: "127.0.0.1",
  port: 8443,
  ssl: [
    keyfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca-client-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca-client.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]
