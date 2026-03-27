import Config

alias NervesHub.Accounts.Scope
alias NervesHub.Workers.CleanStaleDeviceConnections
alias NervesHub.Workers.CleanUpSoftDeletedDevices
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
  ]

config :flop, repo: NervesHub.Repo

config :mime, :types, %{
  "application/pem" => ["pem"],
  "application/crt" => ["crt"],
  "application/fwup" => ["fw"]
}

config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000,
  migration_lock: :pg_advisory_lock

config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NervesHubWeb.ErrorDeviceHTML, json: ErrorJSON],
    accepts: ~w(html json)
  ],
  pubsub_server: NervesHub.PubSub

config :nerves_hub, NervesHubWeb.Endpoint,
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
  repo: NervesHub.Repo,
  notifier: Oban.Notifiers.PG,
  log: false,
  queues: [
    default: 1,
    delete_archive: 1,
    delete_firmware: 1,
    device: 1,
    firmware_delta_builder: 2,
    firmware_delta_timeout: 1,
    truncate: 1,
    # temporary, will remove in November
    truncation: 1
  ],
  plugins: [
    # 1 week
    {Oban.Plugins.Pruner, max_age: 604_800},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", ScheduleOrgAuditLogTruncation},
       {"*/1 * * * *", CleanStaleDeviceConnections},
       {"* * * * *", FirmwareDeltaTimeout},
       {"*/5 * * * *", ExpireInflightUpdates},
       {"*/15 * * * *", DeviceHealthTruncation},
       {"*/15 * * * *", CleanUpSoftDeletedDevices}
     ]}
  ]

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

config :ueberauth, Ueberauth,
  providers: [
    google: {Google, [default_scope: "email profile openid"]}
  ]

# Environment specific config
import_config "#{Mix.env()}.exs"
