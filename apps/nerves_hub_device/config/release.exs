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

config :ex_aws, region: System.fetch_env!("AWS_REGION")

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint, server: true

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

# OTP 25.2 includes SSL 10.8.6 which allows disabling certificate authorities
# check with Client SSL since we don't expect devices to send full chains
# up to NervesHub. This allows the use of TLS 1.3.

# However, hardware in production was changed to force tlsv1.2
# which breaks attempting to use ATTEC508A crypto engine with servers
# running TLS 1.3. So before migrating there, we need to transition
# devices to support TLS 1.2 or 1.3
#
# see https://github.com/smartrent/nerves_hub_web#potential-ssl-issues
tls_opts = [versions: [:"tlsv1.2"]]

# Once migrated, remove the line above and uncomment these lines

# ssl_ver = to_string(Application.spec(:ssl)[:vsn])

# tls_opts =
#   if Version.match?(ssl_ver, ">= 10.8.6") do
#     [certificate_authorities: false]
#   else
#     [versions: [:"tlsv1.2"]]
#   end

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  url: [host: host],
  https:
    [
      port: 443,
      otp_app: :nerves_hub_device,
      # Enable client SSL
      verify: :verify_peer,
      fail_if_no_peer_cert: true,
      keyfile: "/etc/ssl/#{host}-key.pem",
      certfile: "/etc/ssl/#{host}.pem",
      cacertfile: "/etc/ssl/ca.pem"
    ] ++ tls_opts

config :nerves_hub_web_core, NervesHubWebCore.Tracer, env: System.get_env("DD_ENV") || "dev"
