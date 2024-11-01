import Config

nerves_hub_app = System.get_env("NERVES_HUB_APP", "all")

unless Enum.member?(["all", "web", "device"], nerves_hub_app) do
  raise """
  unknown value \"#{nerves_hub_app}\" for NERVES_HUB_APP
  supported values are \"all\", \"web\", and \"device\"
  """
end

config :nerves_hub,
  app: nerves_hub_app,
  deploy_env: System.get_env("DEPLOY_ENV", to_string(config_env())),
  log_include_mfa: System.get_env("LOG_INCLUDE_MFA", "false") == "true",
  web_title_suffix: System.get_env("WEB_TITLE_SUFFIX", "NervesHub"),
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org"),
  email_sender: System.get_env("EMAIL_SENDER", "NervesHub"),
  support_email_platform_name: System.get_env("SUPPORT_EMAIL_PLATFORM_NAME", "NervesHub"),
  support_email_address: System.get_env("SUPPORT_EMAIL_ADDRESS"),
  support_email_signoff: System.get_env("SUPPORT_EMAIL_SIGNOFF"),
  device_endpoint_redirect:
    System.get_env("DEVICE_ENDPOINT_REDIRECT", "https://docs.nerves-hub.org/"),
  admin_auth: [
    username: System.get_env("ADMIN_AUTH_USERNAME"),
    password: System.get_env("ADMIN_AUTH_PASSWORD")
  ],
  device_health_check_enabled: System.get_env("DEVICE_HEALTH_CHECK_ENABLED", "true") == "true",
  device_health_check_interval_minutes:
    String.to_integer(System.get_env("DEVICE_HEALTH_CHECK_INTERVAL_MINUTES", "60")),
  device_health_days_to_retain:
    String.to_integer(System.get_env("HEALTH_CHECK_DAYS_TO_RETAIN", "7")),
  device_deployment_change_jitter_seconds:
    String.to_integer(System.get_env("DEVICE_DEPLOYMENT_CHANGE_JITTER_SECONDS", "10")),
  device_last_seen_update_interval_minutes:
    String.to_integer(System.get_env("DEVICE_LAST_SEEN_UPDATE_INTERVAL_MINUTES", "5")),
  deployment_calculator_interval_seconds:
    String.to_integer(System.get_env("DEPLOYMENT_CALCULATOR_INTERVAL_SECONDS", "3600")),
  mapbox_access_token: System.get_env("MAPBOX_ACCESS_TOKEN"),
  dashboard_enabled: System.get_env("DASHBOARD_ENABLED", "false") == "true"

config :nerves_hub, :device_socket_drainer,
  batch_size: String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_BATCH_SIZE", "1000")),
  batch_interval:
    String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_BATCH_INTERVAL", "4000")),
  shutdown: String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_SHUTDOWN", "30000"))

# only set this in :prod as not to override the :dev config
if config_env() == :prod do
  config :nerves_hub,
    open_for_registrations: System.get_env("OPEN_FOR_REGISTRATIONS", "false") == "true"

  # Configures Elixir's Logger
  config :logger, :default_formatter,
    format: {NervesHub.Logger, :format},
    metadata: :all

  config :logfmt_ex, :opts,
    message_key: "msg",
    timestamp_key: "ts",
    timestamp_format: :iso8601
end

if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_atom(level)
end

##
# Web and Device endpoints
#
if config_env() == :prod do
  if nerves_hub_app in ["all", "web"] do
    host =
      System.get_env("WEB_HOST") || System.get_env("HOST") ||
        raise """
        environment variable WEB_HOST or HOST must be set.
        For example: mynerveshub.com
        """

    port = System.get_env("HTTP_PORT") || System.get_env("PORT") || "4000"

    config :nerves_hub, NervesHubWeb.Endpoint,
      url: [
        host: host,
        scheme: System.get_env("WEB_SCHEME", "https"),
        port: String.to_integer(System.get_env("WEB_PORT", "443"))
      ],
      http: [
        port: String.to_integer(port)
      ],
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
      live_view: [
        signing_salt: System.fetch_env!("LIVE_VIEW_SIGNING_SALT")
      ],
      server: true
  end

  if nerves_hub_app in ["all", "device"] do
    host =
      System.get_env("DEVICE_HOST") || System.get_env("WEB_HOST") || System.get_env("HOST") ||
        raise """
        environment variable DEVICE_HOST, WEB_HOST, or HOST must be set.
        For example: device.mynerveshub.com
        """

    https_port = String.to_integer(System.get_env("DEVICE_PORT", "443"))

    keyfile =
      if System.get_env("DEVICE_SSL_KEY") do
        ssl_key = System.fetch_env!("DEVICE_SSL_KEY") |> Base.decode64!()
        File.mkdir_p!("/app/tmp")
        File.write!("/app/tmp/ssl_key.crt", ssl_key)
        "/app/tmp/ssl_key.crt"
      else
        ssl_keyfile = System.get_env("DEVICE_SSL_KEYFILE", "/etc/ssl/#{host}-key.pem")

        if File.exists?(ssl_keyfile) do
          ssl_keyfile
        else
          raise "Could not find keyfile"
        end
      end

    certfile =
      if encoded_cert = System.get_env("DEVICE_SSL_CERT") do
        ssl_cert = Base.decode64!(encoded_cert)
        File.mkdir_p!("/app/tmp")
        File.write!("/app/tmp/ssl_cert.crt", ssl_cert)
        "/app/tmp/ssl_cert.crt"
      else
        ssl_certfile = System.get_env("DEVICE_SSL_CERTFILE", "/etc/ssl/#{host}.pem")

        if File.exists?(ssl_certfile) do
          ssl_certfile
        else
          raise "Could not find certfile"
        end
      end

    cacertfile =
      if cacertfile = System.get_env("DEVICE_SSL_CACERTFILE") do
        if File.exists?(cacertfile) do
          cacertfile
        else
          raise "Could not find certfile"
        end
      else
        CAStore.file_path()
      end

    transport_options = [
      verify: :verify_peer,
      verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
      fail_if_no_peer_cert: false,
      keyfile: keyfile,
      certfile: certfile,
      cacertfile: cacertfile,
      hibernate_after: 15_000
    ]

    # Older versions of OTP 25 may break using using devices
    # that support TLS 1.3 or 1.2 negotiation. To mitigate that
    # potential error, by default we enforce TLS 1.2.
    # If you're using OTP >= 25.1 on all devices, then it is safe to
    # allow TLS 1.3 and setting `certificate_authorities: false` since we
    # don't expect devices to send full chains to the server
    # See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
    transport_options =
      if System.get_env("DEVICE_ENABLE_TLS_13", "false") == "true" do
        transport_options ++ [certificate_authorities: false]
      else
        transport_options ++ [versions: [:"tlsv1.2"]]
      end

    config :nerves_hub, NervesHubWeb.DeviceEndpoint,
      url: [host: host],
      https: [
        port: https_port,
        otp_app: :nerves_hub,
        http_options: [
          log_protocol_errors: false
        ],
        thousand_island_options: [
          transport_module: NervesHub.DeviceSSLTransport,
          transport_options: transport_options
        ]
      ]
  end

  config :nerves_hub, NervesHubWeb.DeviceSocket,
    shared_secrets: [
      enabled: System.get_env("DEVICE_SHARED_SECRETS_ENABLED", "false") == "true"
    ]
end

##
# Database and Libcluster connection settings
#
if config_env() == :prod do
  database_ssl_opts =
    if System.get_env("DATABASE_SSL", "true") == "true" do
      if System.get_env("DATABASE_PEM") do
        db_hostname_charlist =
          ~r/.*@(?<hostname>[^:\/]+)(?::\d+)?\/.*/
          |> Regex.named_captures(System.fetch_env!("DATABASE_URL"))
          |> Map.get("hostname")
          |> to_charlist()

        cacerts =
          System.fetch_env!("DATABASE_PEM")
          |> Base.decode64!()
          |> :public_key.pem_decode()
          |> Enum.map(fn {_, der, _} -> der end)

        [
          verify: :verify_peer,
          cacerts: cacerts,
          server_name_indication: db_hostname_charlist
        ]
      else
        [cacerts: :public_key.cacerts_get()]
      end
    else
      false
    end

  database_socket_options = if System.get_env("DATABASE_INET6") == "true", do: [:inet6], else: []

  config :nerves_hub, NervesHub.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: database_ssl_opts,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "20")),
    socket_options: database_socket_options,
    queue_target: 5000

  oban_pool_size =
    System.get_env("OBAN_DATABASE_POOL_SIZE") || System.get_env("DATABASE_POOL_SIZE", "20")

  config :nerves_hub, NervesHub.ObanRepo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: database_ssl_opts,
    pool_size: String.to_integer(oban_pool_size),
    socket_options: database_socket_options,
    queue_target: 5000

  config :nerves_hub,
    database_auto_migrator: System.get_env("DATABASE_AUTO_MIGRATOR", "true") == "true"

  # Libcluster is using Postgres for Node discovery
  # The library only accepts keyword configs, so the DATABASE_URL has to be
  # parsed and put together with the ssl pieces from above.
  postgres_config = Ecto.Repo.Supervisor.parse_url(System.fetch_env!("DATABASE_URL"))

  libcluster_db_config =
    [port: 5432]
    |> Keyword.merge(postgres_config)
    |> Keyword.take([:hostname, :username, :password, :database, :port])
    |> Keyword.merge(ssl: database_ssl_opts)
    |> Keyword.merge(parameters: [])
    |> Keyword.merge(channel_name: "nerves_hub_clustering")

  config :libcluster,
    topologies: [
      postgres: [
        strategy: LibclusterPostgres.Strategy,
        config: libcluster_db_config
      ]
    ]
end

##
# Firmware upload backend.
#
if config_env() == :prod do
  firmware_upload = System.get_env("FIRMWARE_UPLOAD_BACKEND", "local")

  case firmware_upload do
    "S3" ->
      config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.S3

      config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.S3

      config :nerves_hub, NervesHub.Uploads.S3, bucket: System.fetch_env!("S3_BUCKET_NAME")

      config :nerves_hub, NervesHub.Firmwares.Upload.S3,
        bucket: System.fetch_env!("S3_BUCKET_NAME")

      if System.get_env("S3_ACCESS_KEY_ID") do
        config :ex_aws, :s3,
          access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
          secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY")
      end

      if System.get_env("S3_BUCKET_AS_HOST", "false") == "true" do
        config :nerves_hub, NervesHub.Firmwares.Upload.S3,
          presigned_url_opts: [
            virtual_host: true,
            bucket_as_host: true
          ]
      else
        config :nerves_hub, NervesHub.Firmwares.Upload.S3, presigned_url_opts: []
      end

      config :ex_aws, :s3, bucket: System.fetch_env!("S3_BUCKET_NAME")

      if region = System.get_env("S3_REGION") do
        config :ex_aws, :s3, region: region
      end

      if s3_host = System.get_env("S3_HOST") do
        config :ex_aws, :s3, host: s3_host
      end

      config :ex_aws,
        json_codec: Jason

    "local" ->
      local_path = System.get_env("FIRMWARE_UPLOAD_PATH")

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

    other ->
      raise """
      unsupported firmware backend \"#{other}\"
      only \"local\" and \"S3\" available for selection
      """
  end
end

##
# SMTP settings.
#
if config_env() == :prod do
  config :swoosh, local: false

  if System.get_env("SMTP_SERVER") do
    config :nerves_hub, NervesHub.SwooshMailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: System.fetch_env!("SMTP_SERVER"),
      port: System.fetch_env!("SMTP_PORT") |> String.to_integer(),
      username: System.fetch_env!("SMTP_USERNAME"),
      password: System.fetch_env!("SMTP_PASSWORD"),
      auth: :always,
      ssl: System.get_env("SMTP_SSL", "false") == "true",
      tls: :always,
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 99,
        server_name_indication: String.to_charlist(System.get_env("SMTP_SERVER")),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      retries: 1
  end
end

config :sentry,
  dsn: System.get_env("SENTRY_DSN_URL"),
  environment_name: System.get_env("DEPLOY_ENV", to_string(config_env())),
  enable_source_code_context: true,
  root_source_code_path: [File.cwd!()],
  before_send: {NervesHubWeb.SentryEventFilter, :filter_non_500},
  release: "nerves_hub@#{Application.spec(:nerves_hub, :vsn)}",
  tags: %{
    app: nerves_hub_app
  },
  integrations: [
    oban: [
      # Capture errors:
      capture_errors: true,
      # Monitor cron jobs:
      cron: [enabled: true]
    ]
  ]

if host = System.get_env("STATSD_HOST") do
  config :nerves_hub, :statsd,
    host: System.get_env("STATSD_HOST"),
    port: String.to_integer(System.get_env("STATSD_PORT", "8125"))
end

config :nerves_hub, :audit_logs,
  enabled: System.get_env("TRUNATE_AUDIT_LOGS_ENABLED", "false") == "true",
  default_days_kept:
    String.to_integer(System.get_env("TRUNCATE_AUDIT_LOGS_DEFAULT_DAYS_KEPT", "30"))

config :nerves_hub, NervesHub.RateLimit,
  limit: System.get_env("DEVICE_CONNECT_RATE_LIMIT", "100") |> String.to_integer()
