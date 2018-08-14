use Mix.Config

config :nerves_hub_core, firmware_upload: NervesHubCore.Firmwares.Upload.S3
config :nerves_hub_core, NervesHubCore.Firmwares.Upload.S3, bucket: "${S3_BUCKET_NAME}"

config :nerves_hub_core, NervesHubCore.Repo, adapter: Ecto.Adapters.Postgres

config :nerves_hub_core, NervesHubCore.CertificateAuthority,
  host: "nerves-hub-ca.local",
  port: 8443,
  ssl: [
    keyfile: "/etc/cfssl/ca-client-key.pem",
    certfile: "/etc/cfssl/ca-client.pem",
    cacertfile: "/etc/cfssl/ca.pem",
    server_name_indication: 'ca.nerves-hub.org',
    verify: :verify_peer
  ]
