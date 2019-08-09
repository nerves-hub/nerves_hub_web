import Config

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.trim()
      |> String.split(" ")
      |> Enum.map(&String.to_atom/1)

    :error ->
      []
  end

config :kernel,
  sync_nodes_optional: sync_nodes_optional,
  sync_nodes_timeout: 5000,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9155

if rollbar_access_token = System.get_env("ROLLBAR_ACCESS_TOKEN") do
  config :rollbax, access_token: rollbar_access_token
else
  config :rollbax, enabled: false
end

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Transfer.S3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")

config :ex_aws, region: System.fetch_env!("AWS_REGION")

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

cacert_pems = [
  "/etc/ssl/user-root-ca.pem",
  "/etc/ssl/root-ca.pem"
]

cacerts =
  cacert_pems
  |> Enum.map(&File.read!/1)
  |> Enum.map(&X509.Certificate.from_pem!/1)
  |> Enum.map(&X509.Certificate.to_der/1)

config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  url: [host: host],
  https: [
    port: 443,
    otp_app: :nerves_hub_api,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: "/etc/ssl/#{host}-key.pem",
    certfile: "/etc/ssl/#{host}.pem",
    cacerts: cacerts ++ :certifi.cacerts()
  ]

ca_host = System.fetch_env!("CA_HOST")

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: ca_host,
  port: 8443,
  ssl: [
    keyfile: "/etc/ssl/#{host}-key.pem",
    certfile: "/etc/ssl/#{host}.pem",
    cacertfile: "/etc/ssl/ca.pem"
  ]
