use Mix.Config

config :nerves_hub_core, firmware_upload: NervesHubCore.Firmwares.Upload.File

config :nerves_hub_core, NervesHubCore.Firmwares.Upload.File,
  local_path: Path.join(System.tmp_dir(), "firmware"),
  public_path: "/firmware"

# config :nerves_hub_core, NervesHubCore.Firmwares.Upload.S3, bucket: System.get_env("S3_BUCKET_NAME")

config :nerves_hub_core, NervesHubCore.Repo, ssl: false

config :nerves_hub_core, NervesHubCore.CertificateAuthority,
  host: "0.0.0.0",
  port: 8443,
  ssl: [
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]
