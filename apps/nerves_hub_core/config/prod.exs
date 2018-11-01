use Mix.Config

config :ex_aws,
  region: "${AWS_REGION}"

config :nerves_hub_core, firmware_upload: NervesHubCore.Firmwares.Upload.S3
config :nerves_hub_core, NervesHubCore.Firmwares.Upload.S3, bucket: "${S3_BUCKET_NAME}"

config :nerves_hub_core, NervesHubCore.CertificateAuthority,
  host: "nerves-hub-ca.local",
  port: 8443,
  ssl: [
    keyfile: "/etc/ssl/ca-client-key.pem",
    certfile: "/etc/ssl/ca-client.pem",
    cacertfile: "/etc/ssl/ca.pem",
    server_name_indication: 'ca.nerves-hub.org'
  ]
