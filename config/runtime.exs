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
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

if level = System.get_env("LOG_LEVEL") do
  config :logger, level: String.to_atom(level)
end

dns_cluster_query =
  if System.get_env("DNS_CLUSTER_QUERY") do
    System.get_env("DNS_CLUSTER_QUERY") |> String.split(",")
  else
    nil
  end

config :nerves_hub, dns_cluster_query: dns_cluster_query

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

    config :nerves_hub, NervesHubWeb.DeviceSocketSharedSecretAuth,
      enabled: System.get_env("DEVICE_SHARED_SECRET_AUTH", "false") == "true"
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
        :ok = File.write("/app/tmp/ssl_key.crt", ssl_key)
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
        :ok = File.write("/app/tmp/ssl_cert.crt", ssl_cert)
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

    config :nerves_hub, NervesHubWeb.DeviceEndpoint,
      url: [host: host],
      https: [
        port: https_port,
        otp_app: :nerves_hub,
        thousand_island_options: [
          transport_module: NervesHub.DeviceSSLTransport,
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
            versions: [:"tlsv1.2"],
            verify: :verify_peer,
            verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
            fail_if_no_peer_cert: true,
            keyfile: keyfile,
            certfile: certfile,
            cacertfile: cacertfile,
            hibernate_after: 15_000
          ]
        ]
      ]

    if System.get_env("AWS_IOT_ENABLED") in ["1", "true", "t"] do
      config :nerves_hub, NervesHub.AWSIoT,
        queues: [
          [
            # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set
            name: :nerves_hub_iot_messages,
            producer: [
              module:
                {BroadwaySQS.Producer,
                 queue_url: System.get_env("AWS_IOT_SQS_QUEUE", "nerves-hub-iot-messages")}
            ],
            processors: [default: []],
            batchers: [default: [batch_size: 10, batch_timeout: 2000]]
          ]
        ]
    end
  end
end

##
# Database and Libcluster connection settings
#
if config_env() == :prod do
  database_ssl_opts =
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

  database_socket_options = if System.get_env("DATABASE_INET6") == "true", do: [:inet6], else: []

  config :nerves_hub, NervesHub.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: System.get_env("DATABASE_SSL", "true") == "true",
    ssl_opts: database_ssl_opts,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "20")),
    socket_options: database_socket_options,
    queue_target: 5000

  oban_pool_size =
    System.get_env("OBAN_DATABASE_POOL_SIZE") || System.get_env("DATABASE_POOL_SIZE", "20")

  config :nerves_hub, NervesHub.ObanRepo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: System.get_env("DATABASE_SSL", "true") == "true",
    ssl_opts: database_ssl_opts,
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
    |> Keyword.merge(ssl: System.get_env("DATABASE_SSL", "true") == "true")
    |> Keyword.merge(ssl_opts: database_ssl_opts)
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
      port: System.fetch_env!("SMTP_PORT"),
      username: System.fetch_env!("SMTP_USERNAME"),
      password: System.fetch_env!("SMTP_PASSWORD"),
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

if System.get_env("SENTRY_DSN_URL") do
  config :sentry,
    dsn: System.get_env("SENTRY_DSN_URL"),
    environment_name: System.get_env("DEPLOY_ENV", to_string(config_env())),
    enable_source_code_context: true,
    root_source_code_path: File.cwd!()
end

config :nerves_hub, :statsd,
  host: System.get_env("STATSD_HOST", "localhost"),
  port: String.to_integer(System.get_env("STATSD_PORT", "8125"))

config :nerves_hub, :audit_logs,
  enabled: System.get_env("TRUNATE_AUDIT_LOGS_ENABLED", "false") == "true",
  max_records_per_run:
    String.to_integer(System.get_env("TRUNCATE_AUDIT_LOGS_MAX_RECORDS_PER_RUN", "10000")),
  days_kept: String.to_integer(System.get_env("TRUNCATE_AUDIT_LOGS_MAX_DAYS_KEPT", "30"))

config :nerves_hub, NervesHub.RateLimit,
  limit: System.get_env("DEVICE_CONNECT_RATE_LIMIT", "100") |> String.to_integer()

config :nerves_hub, NervesHub.NodeReporter,
  enabled: System.get_env("NODE_REPORTER", "false") == "true"

config :nerves_hub, NervesHub.LoadBalancer,
  enabled: System.get_env("LOAD_BALANCER", "false") == "true"
