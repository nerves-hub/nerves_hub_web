import Config

alias NervesHub.DeviceLink.PeerVerification
alias NervesHub.Devices.DeviceMessages
alias NervesHub.Firmwares.Upload
alias NervesHub.Firmwares.Upload.S3
alias NervesHub.Repo
alias NervesHub.Telemetry.FilteredSampler
alias Sentry.OpenTelemetry.Sampler
alias Sentry.OpenTelemetry.SpanProcessor
alias Swoosh.Adapters.SMTP
alias Ueberauth.Strategy.Google.OAuth

nerves_hub_app = System.get_env("NERVES_HUB_APP", "all")

if !Enum.member?(["all", "web", "device"], nerves_hub_app) do
  raise """
  unknown value \"#{nerves_hub_app}\" for NERVES_HUB_APP
  supported values are \"all\", \"web\", and \"device\"
  """
end

# Shared-session SSO, read at BOOT so it works in dev without
# recompiling. SESSION_COOKIE_DOMAIN scopes the session cookie to a parent domain
# (e.g. ".example.ngrok.io") so apps on a sibling subdomain can read it;
# LOGIN_RETURN_URLS_ALLOWED_LIST lists the urls that login may return to.
if domain = System.get_env("SESSION_COOKIE_DOMAIN") do
  config :nerves_hub, session_cookie_domain: domain
end

config :nerves_hub, :device_socket_drainer,
  batch_size: String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_BATCH_SIZE", "1000")),
  batch_interval: String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_BATCH_INTERVAL", "4000")),
  shutdown: String.to_integer(System.get_env("DEVICE_SOCKET_DRAINER_SHUTDOWN", "30000"))

# Allow login to return to other urls
# See NervesHubWeb.Auth.return_to_target/1.
config :nerves_hub,
       :external_login_return_urls,
       System.get_env("LOGIN_RETURN_URLS_ALLOWED_LIST", "") |> String.split(",", trim: true)

config :nerves_hub,
  app: nerves_hub_app,
  deploy_env: System.get_env("DEPLOY_ENV", to_string(config_env())),
  log_include_mfa: System.get_env("LOG_INCLUDE_MFA", "false") == "true",
  web_title_suffix: System.get_env("WEB_TITLE_SUFFIX", "NervesHub"),
  esp_idf_firmware_enabled: System.get_env("ESP_IDF_FIRMWARE_ENABLED", "false") == "true",
  atomvm_firmware_enabled: System.get_env("ATOMVM_FIRMWARE_ENABLED", "false") == "true",
  rauc_firmware_enabled: System.get_env("RAUC_FIRMWARE_ENABLED", "false") == "true",
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org"),
  email_sender: System.get_env("EMAIL_SENDER", "NervesHub"),
  support_email_platform_name: System.get_env("SUPPORT_EMAIL_PLATFORM_NAME", "NervesHub"),
  support_email_address: System.get_env("SUPPORT_EMAIL_ADDRESS"),
  support_email_signoff: System.get_env("SUPPORT_EMAIL_SIGNOFF"),
  device_endpoint_redirect: System.get_env("DEVICE_ENDPOINT_REDIRECT", "https://docs.nerves-hub.org/"),
  device_health_days_to_retain: String.to_integer(System.get_env("HEALTH_CHECK_DAYS_TO_RETAIN", "7")),
  device_health_delete_limit: String.to_integer(System.get_env("DEVICE_HEALTH_DELETE_LIMIT", "100000")),
  device_last_seen_update_interval_minutes:
    String.to_integer(System.get_env("DEVICE_LAST_SEEN_UPDATE_INTERVAL_MINUTES", "15")),
  device_last_seen_update_interval_jitter_seconds:
    String.to_integer(System.get_env("DEVICE_LAST_SEEN_UPDATE_INTERVAL_JITTER_SECONDS", "300")),
  device_connection_update_limit: String.to_integer(System.get_env("DEVICE_CONNECTION_UPDATE_LIMIT", "100000")),
  device_metrics: [
    max_keys_per_report: String.to_integer(System.get_env("DEVICE_METRICS_MAX_KEYS_PER_REPORT", "20"))
  ],
  mapbox_access_token: System.get_env("MAPBOX_ACCESS_TOKEN"),
  extension_config: [
    geo: [
      # No interval, fetch geo on device connection by default
      interval_minutes: System.get_env("FEATURES_GEO_INTERVAL_MINUTES", "0") |> String.to_integer()
    ],
    health: [
      interval_minutes: System.get_env("FEATURES_HEALTH_INTERVAL_MINUTES", "60") |> String.to_integer(),
      ui_polling_seconds: System.get_env("FEATURES_HEALTH_UI_POLLING_SECONDS", "60") |> String.to_integer()
    ],
    metrics: [
      interval_minutes: System.get_env("FEATURES_METRICS_INTERVAL_MINUTES", "15") |> String.to_integer(),
      ui_polling_seconds: System.get_env("FEATURES_METRICS_UI_POLLING_SECONDS", "60") |> String.to_integer()
    ],
    logging: [
      days_to_keep: String.to_integer(System.get_env("EXTENSIONS_LOGGING_DAYS_TO_KEEP", "3"))
    ]
  ],
  logger_exclusions: System.get_env("LOGGER_EXCLUSIONS", "") |> String.split(","),
  devices_websocket_url:
    System.get_env("DEVICES_WEBSOCKET_HOST") || System.get_env("DEVICE_HOST") || System.get_env("WEB_HOST") ||
      System.get_env("HOST"),
  # Some devices connect to the management host instead of the device host. When
  # enabled, the management endpoint answers those connections with a redirect to
  # `:devices_websocket_url` instead of serving them.
  redirect_to_devices_websocket_url: System.get_env("REDIRECT_TO_DEVICES_WEBSOCKET_URL", "false") == "true",
  clean_up_soft_deleted_devices: System.get_env("CLEAN_UP_SOFT_DELETED_DEVICES", "false") == "true",
  default_lifo_deployment_queue: System.get_env("DEFAULT_LIFO_DEPLOYMENT_QUEUE", "false") == "true",
  featurebase_app_id: System.get_env("FEATUREBASE_APP_ID"),
  featurebase_signing_token: System.get_env("FEATUREBASE_SIGNING_TOKEN"),
  logo_url: System.get_env("LOGO_URL"),
  logo_url_light: System.get_env("LOGO_URL_LIGHT"),
  logo_url_dark: System.get_env("LOGO_URL_DARK")

# only set this in :prod as not to override the :dev config
if config_env() == :prod do
  config :logfmt_ex, :opts,
    message_key: "msg",
    timestamp_key: "ts",
    timestamp_format: :iso8601

  # Configures Elixir's Logger
  config :logger, :default_formatter,
    format: {NervesHub.Logger, :format},
    metadata: :all

  config :nerves_hub,
    open_for_registrations: System.get_env("OPEN_FOR_REGISTRATIONS", "false") == "true"
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

    # Devices can reach us here as well as on the device endpoint, and here TLS is
    # terminated by whatever is in front of us -- so the socket's peer is that
    # balancer, and the device's own address arrives in a header. `x-forwarded-for`
    # is near enough universal among balancers to be the default, and a deployment
    # with nothing in front of it should set this to "none": the header is then
    # only ever whatever the device chose to send, and believing it would let a
    # device write its own address into its connection record.
    forwarded_ip_header =
      System.get_env("WEB_FORWARDED_IP_HEADER", "x-forwarded-for")
      |> String.downcase()
      |> case do
        disabled when disabled in ["", "none"] ->
          nil

        header ->
          if not String.starts_with?(header, "x-") do
            raise """
            WEB_FORWARDED_IP_HEADER was set to #{inspect(header)}, and it has to start with "x-"
            (or be "none", to trust no header at all).

            Phoenix passes a socket only the request headers with that prefix, so any other
            header never reaches the code that would read it and the setting would quietly do
            nothing. Behind Fly.io keep "x-forwarded-for", which "fly-client-ip" cannot
            replace for that reason, and set WEB_FORWARDED_IP_TRAILING_HOPS=1 so the app's
            own anycast address at the end of it is skipped.
            """
          end

          header
      end

    # How many entries at the end of that header were added by infrastructure
    # rather than by the device. The address is counted from the right, so this
    # decides which entry is read. Fly.io appends two -- the address it observed
    # and then the app's own anycast address -- so it needs 1, while a proxy that
    # appends only its own observation needs 0. Confirm it against a real request:
    # the wrong count reads a plausible looking address off the wrong machine.
    forwarded_ip_trailing_hops = String.to_integer(System.get_env("WEB_FORWARDED_IP_TRAILING_HOPS", "0"))

    # Whether the API rate limiter buckets by that header rather than by the
    # socket's peer. Separate from naming the header because the two carry
    # different risk: a forged address that is only recorded is bad data, while
    # one the limiter believes lets a caller pick its own bucket and evade the
    # limit entirely.
    rate_limit_by_forwarded_ip = System.get_env("WEB_RATE_LIMIT_BY_FORWARDED_IP", "false") == "true"

    if rate_limit_by_forwarded_ip and is_nil(forwarded_ip_header) do
      raise """
      WEB_RATE_LIMIT_BY_FORWARDED_IP is set, but WEB_FORWARDED_IP_HEADER is "none", so there is
      no header to rate limit by. Name the header whatever is in front overwrites, or leave
      both unset.
      """
    end

    config :nerves_hub, NervesHubWeb.Endpoint,
      forwarded_ip_header: forwarded_ip_header,
      forwarded_ip_trailing_hops: forwarded_ip_trailing_hops,
      rate_limit_by_forwarded_ip: rate_limit_by_forwarded_ip,
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
      verify_fun: {&PeerVerification.verify_fun/3, nil},
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

    # When a load balancer passes TLS through to us it hides the device behind
    # its own address, and can't add a forwarding header because it never sees
    # inside the stream. The PROXY protocol is how it tells us who connected.
    # Only v2 is supported; see `NervesHub.DeviceSSLTransport`.
    proxy_protocol =
      case System.get_env("DEVICE_PROXY_PROTOCOL") do
        nil ->
          nil

        "" ->
          nil

        "v2" ->
          :v2

        other ->
          raise """
          DEVICE_PROXY_PROTOCOL was set to #{inspect(other)}, and the only supported value is "v2".

          Version 1 of the PROXY protocol can't be read without risking a read into the TLS
          handshake that follows it, so configure the load balancer to send v2 instead. On
          Fly.io that is `proxy_proto_options = { version = "v2" }`.
          """
      end

    config :nerves_hub, NervesHub.DeviceSSLTransport, proxy_protocol: proxy_protocol

    config :nerves_hub, NervesHubWeb.DeviceEndpoint,
      url: [host: host],
      https: [
        port: https_port,
        otp_app: :nerves_hub,
        http_options: [
          log_protocol_errors: false
        ],
        # The sockets set `compress: true`, so Bandit builds a zlib deflate and
        # inflate context per connection and holds both for as long as the
        # device stays connected. At the default mem_level of 8 the deflate
        # hash table alone is 128KB, and measured end to end that is 271KB per
        # device -- around 375MB of `:erlang.memory(:system)` on a node holding
        # 1400 devices.
        #
        # Device frames are small and repetitive, so the hash table buys
        # nothing here: over a representative mix of heartbeats, progress and
        # health reports, mem_level 4 emits byte-identical output to mem_level
        # 8. It costs 121KB less per connection.
        #
        # This has to live in Bandit's server-wide `websocket_options`. Bandit
        # reads `deflate_options` from there, not from the per-socket
        # `websocket:` list in the endpoint.
        websocket_options: [deflate_options: [mem_level: 4]],
        thousand_island_options: [
          transport_module: NervesHub.DeviceSSLTransport,
          transport_options: transport_options
        ]
      ]
  end

  if nerves_hub_app == "device" do
    host = System.get_env("DEVICE_HOST") || System.get_env("WEB_HOST") || System.get_env("HOST")
    port = String.to_integer(System.get_env("DEVICE_HOST_STATUS_PORT", "4040"))

    config :nerves_hub, NervesHubWeb.HealthCheckEndpoint,
      url: [host: host],
      http: [port: port],
      adapter: Bandit.PhoenixAdapter,
      server: true
  end

  config :nerves_hub, NervesHubWeb.DeviceSocket,
    shared_secrets: [
      enabled: System.get_env("DEVICE_SHARED_SECRETS_ENABLED", "false") == "true"
    ]
end

##
# Database and Libcluster connection settings
#

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

      verify =
        if System.get_env("DATABASE_CERT_SELF_SIGNED", "false") == "true" do
          [verify: :verify_none, verify_fun: {&Repo.verify_fun/3, {:der_bin, List.first(cacerts)}}]
        else
          [verify: :verify_peer]
        end

      [
        cacerts: cacerts,
        server_name_indication: db_hostname_charlist
      ] ++ verify
    else
      [cacerts: :public_key.cacerts_get()]
    end
  else
    false
  end

if config_env() == :prod do
  database_socket_options = if System.get_env("DATABASE_INET6") == "true", do: [:inet6], else: []

  config :nerves_hub, NervesHub.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    ssl: database_ssl_opts,
    pool_size: String.to_integer(System.get_env("DATABASE_POOL_SIZE", "20")),
    pool_count: String.to_integer(System.get_env("DATABASE_POOL_COUNT", "1")),
    socket_options: database_socket_options,
    queue_target: 5_000

  config :nerves_hub,
    database_auto_migrator: System.get_env("DATABASE_AUTO_MIGRATOR", "true") == "true"
end

if config_env() == :prod do
  if clickhouse_url = System.get_env("CLICKHOUSE_URL") do
    # Required for Clickhouse Cloud (https://github.com/plausible/analytics/discussions/3497)
    # (using a default order will cause issues for the migration table)
    config :ecto_ch, default_table_engine: "MergeTree"

    # Batch sizing lives in `:analytics_buffer` below, shared with the other
    # analytics write paths. This is only the cap on how much of a single
    # message body is kept.
    config :nerves_hub, DeviceMessages,
      max_payload_bytes: String.to_integer(System.get_env("DEVICE_MESSAGES_MAX_PAYLOAD_BYTES", "8192"))

    config :nerves_hub, NervesHub.AnalyticsRepo,
      url: clickhouse_url,
      pool_size: String.to_integer(System.get_env("ANALYTICS_POOL_SIZE", "10")),
      pool_count: String.to_integer(System.get_env("ANALYTICS_POOL_COUNT", "1")),
      queue_target: 3_000

    config :nerves_hub, :analytics_buffer,
      max_batch_size: String.to_integer(System.get_env("ANALYTICS_BUFFER_MAX_BATCH_SIZE", "1000")),
      max_delay: to_timeout(millisecond: String.to_integer(System.get_env("ANALYTICS_BUFFER_MAX_DELAY_MS", "500"))),
      max_buffer_size: String.to_integer(System.get_env("ANALYTICS_BUFFER_MAX_SIZE", "50000"))

    config :nerves_hub,
      analytics_auto_migrator: System.get_env("ANALYTICS_AUTO_MIGRATOR", "true") == "true"

    config :nerves_hub, analytics_enabled: true
  else
    config :nerves_hub, analytics_enabled: false
  end
end

# The organisation's Iroh Endpoints page. Read in every environment so it can be
# switched on locally the same way it is in a deployment.
config :nerves_hub,
  org_iroh_endpoints_ui_enabled: System.get_env("ORG_IROH_ENDPOINTS_UI_ENABLED", "false") == "true",
  # Where a deployment sends people who want to know about its own relays —
  # a hosted offering, or an internal runbook for a self-hosted one. The page
  # links to the iroh project either way; this is the deployment's own page,
  # so it is a setting rather than a URL in the source.
  org_iroh_endpoints_info_url: System.get_env("ORG_IROH_ENDPOINTS_INFO_URL"),
  # What to call that link. Falls back to the host of the URL above, which is a
  # fair name for a link and one less thing to set.
  org_iroh_endpoints_info_label: System.get_env("ORG_IROH_ENDPOINTS_INFO_LABEL")

##
# Firmware upload backend.
#
if config_env() == :prod do
  firmware_upload = System.get_env("FIRMWARE_UPLOAD_BACKEND", "local")

  case firmware_upload do
    "S3" ->
      config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.S3
      config :nerves_hub, NervesHub.Uploads.S3, bucket: System.fetch_env!("S3_BUCKET_NAME")
      config :nerves_hub, S3, bucket: System.fetch_env!("S3_BUCKET_NAME")
      config :nerves_hub, firmware_upload: S3

      if System.get_env("S3_ACCESS_KEY_ID") do
        config :ex_aws, :s3,
          access_key_id: System.fetch_env!("S3_ACCESS_KEY_ID"),
          secret_access_key: System.fetch_env!("S3_SECRET_ACCESS_KEY")
      end

      if System.get_env("S3_BUCKET_AS_HOST", "false") == "true" do
        config :nerves_hub, S3,
          presigned_url_opts: [
            virtual_host: true,
            bucket_as_host: true
          ]
      else
        config :nerves_hub, S3, presigned_url_opts: []
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

      config :nerves_hub, NervesHub.Firmwares.Upload.File,
        enabled: true,
        public_path: "/firmware",
        local_path: local_path

      config :nerves_hub, NervesHub.Uploads, backend: NervesHub.Uploads.File

      config :nerves_hub, NervesHub.Uploads.File,
        enabled: true,
        local_path: local_path,
        public_path: "/uploads"

      config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

    other ->
      raise """
      unsupported firmware backend \"#{other}\"
      only \"local\" and \"S3\" available for selection
      """
  end
end

# Set a default max archive upload size of 200MB for all environments
config :nerves_hub, NervesHub.Uploads,
  max_size: System.get_env("ARCHIVE_UPLOAD_MAX_SIZE", "200000000") |> String.to_integer()

# Set a default max firmware upload size of 200MB for all environments
config :nerves_hub, Upload, max_size: System.get_env("FIRMWARE_UPLOAD_MAX_SIZE", "200000000") |> String.to_integer()

##
# SMTP settings.
#
if config_env() == :prod do
  config :swoosh, local: false

  if System.get_env("SMTP_SERVER") do
    tls_versions =
      System.get_env("SMTP_TLS_VERSIONS", "")
      |> String.split(",")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_atom/1)

    tls_opts = if Enum.any?(tls_versions), do: [versions: tls_versions], else: []

    config :nerves_hub, NervesHub.SwooshMailer,
      adapter: SMTP,
      relay: System.fetch_env!("SMTP_SERVER"),
      port: System.fetch_env!("SMTP_PORT") |> String.to_integer(),
      username: System.fetch_env!("SMTP_USERNAME"),
      password: System.fetch_env!("SMTP_PASSWORD"),
      auth: :always,
      ssl: System.get_env("SMTP_SSL", "false") == "true",
      tls: :always,
      tls_options:
        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 99,
          server_name_indication: String.to_charlist(System.get_env("SMTP_SERVER")),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ tls_opts,
      retries: 1
  end
end

config :opentelemetry, :resource, service: %{name: nerves_hub_app}

config :sentry,
  dsn: System.get_env("SENTRY_DSN_URL"),
  environment_name: System.get_env("DEPLOY_ENV", to_string(config_env())),
  before_send: {NervesHubWeb.SentryEventFilter, :filter_non_500},
  release: "nerves_hub@#{Application.spec(:nerves_hub, :vsn)}",
  enable_logs: System.get_env("SENTRY_ENABLE_LOGGING", "false") == "true",
  before_send_log: fn log_event ->
    updated_attributes = Map.put(log_event.attributes, :nerves_hub_app, nerves_hub_app)
    %{log_event | attributes: updated_attributes}
  end,
  logs: [
    metadata: :all
  ],
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

cond do
  System.get_env("SENTRY_ENABLE_TRACING", "false") == "true" ->
    config :opentelemetry, sampler: {Sampler, []}
    config :opentelemetry, span_processor: {SpanProcessor, []}

    config :sentry,
      traces_sampler: fn sampling_context ->
        if sampling_context.transaction_context.name in [
             "nerves_hub.repo.query:oban_jobs",
             "nerves_hub.repo.query:oban_peers"
           ] do
          0.01
        else
          rate = System.get_env("SENTRY_TRACING_RATE", "0.05")
          {parsed, _} = Float.parse(rate)
          parsed
        end
      end

  otlp_endpoint = System.get_env("OTLP_ENDPOINT") ->
    otlp_sampler_ratio =
      if ratio = System.get_env("OTLP_SAMPLER_RATIO") do
        String.to_float(ratio)
      end

    otlp_headers =
      if auth_header = System.get_env("OTLP_AUTH_HEADER") do
        [{auth_header, System.get_env("OTLP_AUTH_HEADER_VALUE")}]
      else
        []
      end

    config :opentelemetry,
      sampler: {:parent_based, %{root: {FilteredSampler, otlp_sampler_ratio}}}

    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: otlp_endpoint,
      otlp_headers: otlp_headers

  true ->
    config :opentelemetry, traces_exporter: :none
end

if host = System.get_env("STATSD_HOST") do
  config :nerves_hub, :statsd,
    host: System.get_env("STATSD_HOST"),
    port: String.to_integer(System.get_env("STATSD_PORT", "8125"))
end

config :nerves_hub, NervesHub.RateLimit,
  limit: System.get_env("DEVICE_CONNECT_RATE_LIMIT", "100") |> String.to_integer()

config :nerves_hub, :audit_logs,
  enabled: System.get_env("TRUNCATE_AUDIT_LOGS_ENABLED", "false") == "true",
  default_days_kept: String.to_integer(System.get_env("TRUNCATE_AUDIT_LOGS_DEFAULT_DAYS_KEPT", "30"))

config :nerves_hub,
  enable_google_auth: !is_nil(System.get_env("GOOGLE_CLIENT_ID"))

if System.get_env("GOOGLE_CLIENT_ID") do
  config :ueberauth, OAuth,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")
end
