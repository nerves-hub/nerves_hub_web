import Config

alias NervesHub.Accounts.Scope
alias NervesHub.Workers.CleanStaleDeviceConnections
alias NervesHub.Workers.CleanUpSoftDeletedDevices
alias NervesHub.Workers.DeleteExpiredCLISessionRecords
alias NervesHub.Workers.DeviceHealthTruncation
alias NervesHub.Workers.ExpireInflightUpdates
alias NervesHub.Workers.FirmwareDeltaTimeout
alias NervesHub.Workers.ScheduleOrgAuditLogTruncation
alias NervesHubWeb.API.ErrorJSON
alias Phoenix.LiveView.Engine
alias Swoosh.ApiClient.Finch
alias Ueberauth.Strategy.Google

# Used by spellweaver
config :bun, :version, "1.2.18"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.2",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2021 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --loader:.png=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  stoplight: [
    args:
      ~w(js/stoplight.js --platform=node --bundle --target=es2021 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --loader:.png=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :flop, repo: NervesHub.Repo

config :mime, :types, %{
  "application/pem" => ["pem"],
  "application/crt" => ["crt"],
  "application/fwup" => ["fw"],
  # RAUC has no registered IANA type. This exists because `allow_upload`
  # refuses any extension it cannot resolve to one, so without it `.raucb`
  # cannot appear in the firmware upload's accept list at all.
  "application/rauc-bundle" => ["raucb"],
  # Same for AtomVM packbeams, and the failure is worse than a rejected
  # upload: an unknown extension in `accept` raises out of `allow_upload`, so
  # the firmware page does not render at all.
  "application/avm" => ["avm"]
}

# Devices authenticate with client certificates, so TLS terminates in the app
# rather than at a load balancer. Set `proxy_protocol: :v2` when something in
# front of us passes TLS through and announces the device with a PROXY protocol
# header. See `NervesHub.DeviceSSLTransport`.
config :nerves_hub, NervesHub.DeviceSSLTransport, proxy_protocol: nil

config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000,
  migration_lock: :pg_advisory_lock

config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  # Deliberately trusts no forwarding header, unlike the web endpoint: TLS
  # terminates here, so nothing in front of us can reach into the stream to set
  # one, and a forwarding header arriving on this endpoint could only have been
  # written by the device itself.
  forwarded_ip_header: nil,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NervesHubWeb.ErrorDeviceHTML, json: ErrorJSON],
    accepts: ~w(html json)
  ],
  pubsub_server: NervesHub.PubSub

# Devices can also reach us through the web endpoint, where TLS is terminated
# ahead of us and the socket's peer is whatever terminated it. This names the
# header carrying the address that peer saw. Set it to `nil` when the endpoint is
# exposed directly, since then the header is only whatever the device chose to
# send. See `NervesHubWeb.Helpers.ClientIP`.
#
# `rate_limit_by_forwarded_ip` is separate, and off, because rate limiting acts
# on the address rather than recording it. Reading the header is worth doing on
# the chance it is right; bucketing a limit by it is only safe once someone has
# confirmed something in front really does overwrite it, so the throttle stays
# on the socket's peer until then.
config :nerves_hub, NervesHubWeb.Endpoint,
  forwarded_ip_header: "x-forwarded-for",
  forwarded_ip_trailing_hops: 0,
  rate_limit_by_forwarded_ip: false,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "ZH9GG2S5CwIMWXBg92wUuoyKFrjgqaAybHLTLuUk1xZO0HeidcJbnMBSTHDcyhSn",
  live_view: [
    signing_salt: "Kct3W8U7uQ6KAczYjzNbiYS6A8Pbtk3f"
  ],
  render_errors: [
    formats: [html: NervesHubWeb.ErrorHTML, json: ErrorJSON],
    accepts: ~w(html json)
  ],
  pubsub_server: NervesHub.PubSub

config :nerves_hub, NervesHubWeb.Gettext, default_locale: "en"

config :nerves_hub, Oban,
  repo: {NervesHub.Repo, log: false},
  notifier: Oban.Notifiers.PG,
  pruner: [max_age: {1, :week}, interval: {3, :minutes}],
  cron: [
    crontab: [
      {"0 * * * *", ScheduleOrgAuditLogTruncation},
      {"*/1 * * * *", CleanStaleDeviceConnections},
      {"* * * * *", FirmwareDeltaTimeout},
      {"*/5 * * * *", ExpireInflightUpdates},
      {"*/15 * * * *", DeviceHealthTruncation},
      {"*/15 * * * *", CleanUpSoftDeletedDevices}
    ]
  ],
  queues: [
    default: 1,
    firmware: 5,
    delete_file: 3,
    cleanup: 2,
    # temporary, schedule for removal
    delete_archive: 1,
    delete_firmware: 1,
    device: 1,
    firmware_delta_builder: 2,
    firmware_delta_timeout: 1,
    truncate: 1,
    truncation: 1
  ]

# How much of a metric report NervesHub will store. Metric names are
# device-defined, and they become a `LowCardinality` column in ClickHouse, JSONB
# keys in PostgreSQL and entries in the advanced-query autosuggest list, so one
# confused client can widen all three permanently. Overridable in a deployment
# with `DEVICE_METRICS_MAX_KEYS_PER_REPORT`; see `NervesHub.Devices.Metrics`.
config :nerves_hub, :device_metrics, max_keys_per_report: 20

config :nerves_hub, :scopes,
  user: [
    default: true,
    module: Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users
    # test_data_fixture: MyApp.AccountsFixtures,
    # test_setup_helper: :register_and_log_in_user
  ],
  org: [
    module: Scope,
    assign_key: :current_scope,
    access_path: [:org, :id],
    route_prefix: "/org/:org",
    route_access_path: [:org, :name],
    schema_key: :org_id,
    schema_type: :id,
    schema_table: :orgs
    # test_data_fixture: MyApp.AccountsFixtures,
    # test_setup_helper: :register_and_log_in_user_with_org
  ],
  product: [
    module: Scope,
    assign_key: :current_scope,
    access_path: [:product, :id],
    route_prefix: "/product/:product",
    route_access_path: [:product, :name],
    schema_key: :product_id,
    schema_type: :id,
    schema_table: :products
    # test_data_fixture: MyApp.AccountsFixtures,
    # test_setup_helper: :register_and_log_in_user_with_org
  ]

config :nerves_hub,
  env: Mix.env(),
  namespace: NervesHub,
  ecto_repos: [NervesHub.AnalyticsRepo, NervesHub.Repo]

config :phoenix,
  json_library: Jason,
  template_engines: [
    leex: Engine
  ]

config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

config :swoosh, :api_client, Finch

config :tailwind,
  version: "4.2.2",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# disable tzdata auto updates as it is currently broken in 1.1.3
config :tzdata, :autoupdate, :disabled

config :ueberauth, Ueberauth,
  providers: [
    google: {Google, [default_scope: "email profile openid"]}
  ]

# Environment specific config
import_config "#{Mix.env()}.exs"

# An optional link on that page to whoever runs the relays this deployment
# talks to. Deliberately empty here: which relays a deployment uses, and what
# it wants to tell its operators about them, is not something NervesHub knows.
config :nerves_hub, org_iroh_endpoints_info_url: nil, org_iroh_endpoints_info_label: nil

# The organisation's Iroh Endpoints page. Off unless a deployment turns it on,
# since it is only useful where iroh is in use. The switch covers the page
# alone — devices record their iroh identities either way.
config :nerves_hub, org_iroh_endpoints_ui_enabled: false
