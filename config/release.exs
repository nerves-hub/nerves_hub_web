import Config

nerves_hub_app =
  System.get_env("NERVES_HUB_APP")
  |> case do
    "www" -> "web"
    other -> other
  end

config :nerves_hub, app: nerves_hub_app

logger_level = System.get_env("LOG_LEVEL", "info") |> String.to_atom()

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

firmware_upload = System.get_env("FIRMWARE_UPLOAD_BACKEND", "S3")

case firmware_upload do
  "S3" ->
    config :nerves_hub, NervesHub.Firmwares.Upload.S3,
      bucket: System.fetch_env!("S3_BUCKET_NAME")

  "local" ->
    local_path = System.get_env("FIRMWARE_UPLOAD_PATH")

    config :nerves_hub, NervesHub.Firmwares.Upload.File,
      enabled: true,
      local_path: local_path,
      public_path: "/firmware"
end

config :ex_aws, region: System.fetch_env!("AWS_REGION")

config :nerves_hub, NervesHub.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

config :nerves_hub, NervesHub.Tracer, env: System.get_env("DD_ENV") || "dev"

if nerves_hub_app in ["all", "web"] do
  host = System.fetch_env!("HOST")
  port = 80

  config :nerves_hub,
    host: host,
    port: port,
    from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

  config :nerves_hub, NervesHubWeb.Endpoint,
    url: [host: host, port: port],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    live_view: [signing_salt: System.fetch_env!("LIVE_VIEW_SIGNING_SALT")]
end

if nerves_hub_app in ["all", "device"] do
  host = System.get_env("DEVICE_HOST") || System.fetch_env!("HOST")
  https_port = String.to_integer(System.get_env("DEVICE_PORT") || "443")

  config :nerves_hub, NervesHubWeb.DeviceEndpoint,
    url: [host: host],
    https: [
      verify_fun: {&NervesHubDevice.SSL.verify_fun/3, nil},
      port: https_port,
      otp_app: :nerves_hub,
      # Enable client SSL
      # Older versions of OTP 25 may break using using devices
      # that support TLS 1.3 or 1.2 negotiation. To mitigate that
      # potential error, we enforce TLS 1.2. If you're using OTP >= 25.1
      # on all devices, then it is safe to allow TLS 1.3 by removing
      # the versions constraint and setting `certificate_authorities: false`
      # since we don't expect devices to send full chains to the server
      # See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
      #
      # certificate_authorities: false,
      verify: :verify_peer,
      fail_if_no_peer_cert: true,
      keyfile: "/etc/ssl/#{host}-key.pem",
      certfile: "/etc/ssl/#{host}.pem",
      cacertfile: "/etc/ssl/ca.pem"
    ]
end

if nerves_hub_app in ["all", "api"] do
  host = System.get_env("API_HOST") || System.fetch_env!("HOST")
  url_port = String.to_integer(System.get_env("API_URL_PORT") || "80")

  config :nerves_hub, NervesHubWeb.API.Endpoint, url: [host: host, port: url_port]
end
