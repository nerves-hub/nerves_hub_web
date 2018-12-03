use Mix.Config

config :nerves_hub_web_core, firmware_upload: NervesHubWebCore.Firmwares.Upload.File

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.File,
  local_path: Path.join(System.tmp_dir(), "firmware"),
  public_path: "/firmware"

# config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3, bucket: System.get_env("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Repo, ssl: false

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: "0.0.0.0",
  port: 8443,
  ssl: [
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]
