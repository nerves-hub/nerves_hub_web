use Mix.Config

config :bcrypt_elixir,
  log_rounds: 4

config :nerves_hub_web_core, firmware_upload: NervesHubWebCore.Firmwares.Upload.File

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
    keyfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca-client-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca-client.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]
