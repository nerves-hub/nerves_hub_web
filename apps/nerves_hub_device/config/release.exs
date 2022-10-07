import Config

logger_level = System.get_env("LOG_LEVEL", "warn") |> String.to_atom()

config :logger, level: logger_level

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.split(" ", trim: true)
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

config :nerves_hub_web_core,
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Workers.FirmwaresTransferS3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint, server: true

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  url: [host: host],
  https: [
    port: 443,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    versions: [:"tlsv1.2"],
    verify: :verify_peer,
    fail_if_no_peer_cert: true,
    keyfile: "/etc/ssl/#{host}-key.pem",
    certfile: "/etc/ssl/#{host}.pem",
    cacertfile: "/etc/ssl/ca.pem"
  ]
