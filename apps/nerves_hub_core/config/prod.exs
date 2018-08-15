use Mix.Config

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION")

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
