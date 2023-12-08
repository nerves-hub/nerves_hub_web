import Config
import Dotenvy

source!([".env", System.get_env()])

if env!("LOG_LEVEL", :string?, nil) do
  config :logger, level: env!("LOG_LEVEL", :atom!, :info)
end

nerves_hub_app = env!("NERVES_HUB_APP", :string!, "all")

config :nerves_hub, app: nerves_hub_app

config :nerves_hub, deploy_env: env!("DEPLOY_ENV", :string!, to_string(config_env()))

config :nerves_hub, NervesHub.NodeReporter, enabled: env!("NODE_REPORTER", :boolean!, false)

config :nerves_hub, NervesHub.LoadBalancer, enabled: env!("LOAD_BALANCER", :boolean!, false)

dns_cluster_query =
  if env!("DNS_CLUSTER_QUERY", :string!, nil) do
    env!("DNS_CLUSTER_QUERY", :string!) |> String.split(",")
  else
    nil
  end

config :nerves_hub, dns_cluster_query: dns_cluster_query

# Allow for all environments to override the database url
if env!("DATABASE_URL", :string!, nil) do
  config :nerves_hub, NervesHub.Repo,
    url: env!("DATABASE_URL", :string!)

  config :nerves_hub, NervesHub.ObanRepo,
    url: env!("DATABASE_URL", :string!)
end

config :nerves_hub,
  from_email: env!("FROM_EMAIL", :string!, "no-reply@nerves-hub.org")

if env!("OTEL_ENABLED", :boolean!, nil) do
  # Export to a local collector
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: "http://localhost:4318"
end

if config_env() == :prod do
  config :swoosh, local: false

  if env!("SMTP_SERVER", :string!, nil) do
    config :nerves_hub, NervesHub.SwooshMailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: env!("SMTP_SERVER", :string!),
      port: env!("SMTP_PORT", :string!),
      username: env!("SMTP_USERNAME", :string!),
      password: env!("SMTP_PASSWORD", :string!),
      ssl: env!("SMTP_SSL", :boolean?, false),
      tls: :always,
      retries: 1
  end

  config :nerves_hub, NervesHub.RateLimit,
    limit: env!("DEVICE_CONNECT_RATE_LIMIT", :integer!, 100)
end

if config_env() == :prod do
  firmware_upload = env!("FIRMWARE_UPLOAD_BACKEND", :string!, "local")

  case firmware_upload do
    "S3" ->
      config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.S3

      config :nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: env!("S3_BUCKET_NAME", :string!)

      config :ex_aws, :s3,
        access_key_id: env!("S3_ACCESS_KEY_ID", :string!),
        secret_access_key: env!("S3_SECRET_ACCESS_KEY", :string!),
        bucket: env!("S3_BUCKET_NAME", :string!)

      if env!("S3_REGION", :string, nil) do
        config :ex_aws, :s3, region: env!("S3_REGION", :string!)
      end

      if env!("S3_HOST", :string, nil) do
        config :ex_aws, :s3, host: env!("S3_HOST", :string!)
      end

      config :ex_aws,
        json_codec: Jason

    "local" ->
      local_path = env!("FIRMWARE_UPLOAD_PATH", :string!)

      config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

      config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File

      config :nerves_hub, NervesHub.Firmwares.Upload.File,
        enabled: true,
        public_path: "/firmware",
        local_path: local_path

      config :nerves_hub, NervesHub.Uploads.File,
        enabled: true,
        local_path: local_path,
        public_path: "/uploads"
  end
end

config :nerves_hub, :statsd,
  host: env!("STATSD_HOST", :string!, "localhost"),
  port: env!("STATSD_PORT", :integer!, 8125)

config :nerves_hub, :socket_drano,
  enabled: env!("SOCKET_DRAIN_ENABLED", :boolean!, false),
  percentage: env!("SOCKET_DRAIN_BATCH_PERCENTAGE", :integer!, 25),
  time: env!("SOCKET_DRAIN_BATCH_TIME", :integer!, 100)

if config_env() == :prod do
  if nerves_hub_app in ["all", "web"] do
    config :nerves_hub, NervesHubWeb.Endpoint,
      url: [
        host: env!("WEB_HOST", :string!),
        scheme: env!("WEB_SCHEME", :string!, "https"),
        port: env!("WEB_PORT", :integer!, 443)
      ],
      http: [
        port: env!("HTTP_PORT", :integer!, 4000)
      ],
      secret_key_base: env!("SECRET_KEY_BASE", :string!),
      live_view: [
        signing_salt: env!("LIVE_VIEW_SIGNING_SALT", :string!)
      ],
      server: true
  end

  if nerves_hub_app in ["all", "device"] do
    host = env!("DEVICE_HOST", :string!, nil) || env!("WEB_HOST", :string!, nil)
    https_port = env!("DEVICE_PORT", :integer!, 443)

    ssl_key = env!("DEVICE_SSL_KEY", :string!) |> Base.decode64!()
    :ok = File.write("/app/tmp/ssl_key.crt", ssl_key)

    ssl_cert = env!("DEVICE_SSL_CERT", :string!) |> Base.decode64!()
    :ok = File.write("/app/tmp/ssl_cert.crt", ssl_cert)

    config :nerves_hub, NervesHubWeb.DeviceEndpoint,
      url: [host: host],
      https: [
        port: https_port,
        otp_app: :nerves_hub,
        thousand_island_options: [
          transport_options: [
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
            :inet6,
            versions: [:"tlsv1.2"],
            verify: :verify_peer,
            verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
            fail_if_no_peer_cert: true,
            keyfile: "/app/tmp/ssl_key.crt",
            certfile: "/app/tmp/ssl_cert.crt",
            cacertfile: CAStore.file_path()
          ]
        ]
      ]
  end

  #
  # setup Erlang to use CAStore certs by default
  #
  :pubkey_os_cacerts.clear()
  :pubkey_os_cacerts.load([CAStore.file_path()])

  database_ssl_opts =
    if database_pem = env!("DATABASE_PEM", :string!, nil) do
      db_hostname_charlist =
        ~r/.*@(?<hostname>.*):\d{4}\/.*/
        |> Regex.named_captures(env!("DATABASE_URL", :string!))
        |> Map.get("hostname")
        |> to_charlist()

      cacerts =
        database_pem
        |> Base.decode64!()
        |> :public_key.pem_decode()
        |> Enum.map(fn {_, der, _} -> der end)

      [
        verify: :verify_peer,
        cacerts: cacerts,
        server_name_indication: db_hostname_charlist
      ]
    else
      []
    end

  databse_socket_options = if env!("DATABASE_INET6", :boolean!, false), do: [:inet6], else: []

  config :nerves_hub, NervesHub.Repo,
    ssl: env!("DATABASE_SSL", :boolean, true),
    ssl_opts: database_ssl_opts,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("DATABASE_POOL_SIZE", :integer?, 20),
    socket_options: databse_socket_options,
    queue_target: 5000

  config :nerves_hub, NervesHub.ObanRepo,
    ssl: env!("DATABASE_SSL", :boolean, true),
    ssl_opts: database_ssl_opts,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("DATABASE_POOL_SIZE", :integer?, 20),
    socket_options: databse_socket_options,
    queue_target: 5000

  config :nerves_hub,
    database_auto_migrator: env!("DATABASE_AUTO_MIGRATOR", :boolean!, true)
end

if config_env() == :prod and env!("SENTRY_DSN_URL", :string!, nil) do
  config :sentry,
    dsn: env!("SENTRY_DSN_URL", :string!),
    environment_name: env!("DEPLOY_ENV", :string!, to_string(config_env())),
    enable_source_code_context: true,
    root_source_code_path: File.cwd!()
end

config :nerves_hub, :audit_logs,
  enabled: env!("TRUNATE_AUDIT_LOGS_ENABLED", :boolean!, false),
  max_records_per_run: env!("TRUNCATE_AUDIT_LOGS_MAX_RECORDS_PER_RUN", :integer!, 10000),
  days_kept: env!("TRUNCATE_AUDIT_LOGS_MAX_DAYS_KEPT", :integer!, 30)
