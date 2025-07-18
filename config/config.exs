import Config

config :phoenix,
  json_library: Jason,
  template_engines: [
    leex: Phoenix.LiveView.Engine
  ]

config :mime, :types, %{
  "application/pem" => ["pem"],
  "application/crt" => ["crt"],
  "application/fwup" => ["fw"]
}

##
# NervesHub
#
config :nerves_hub,
  env: Mix.env(),
  namespace: NervesHub,
  ecto_repos: [NervesHub.AnalyticsRepo, NervesHub.Repo]

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub Web
#
# cspell:disable
config :nerves_hub, NervesHubWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "ZH9GG2S5CwIMWXBg92wUuoyKFrjgqaAybHLTLuUk1xZO0HeidcJbnMBSTHDcyhSn",
  live_view: [
    signing_salt: "Kct3W8U7uQ6KAczYjzNbiYS6A8Pbtk3f"
  ],
  render_errors: [
    formats: [html: NervesHubWeb.ErrorView, json: NervesHubWeb.API.ErrorJSON],
    accepts: ~w(html json)
  ],
  pubsub_server: NervesHub.PubSub

# cspell:enable
##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000,
  migration_lock: :pg_advisory_lock

config :nerves_hub, Oban,
  repo: NervesHub.ObanRepo,
  notifier: Oban.Notifiers.PG,
  log: false,
  queues: [
    default: 1,
    delete_archive: 1,
    delete_firmware: 1,
    device: 1,
    firmware_delta_builder: 2,
    truncate: 1,
    # temporary, will remove in November
    truncation: 1
  ],
  plugins: [
    # 1 week
    {Oban.Plugins.Pruner, max_age: 604_800},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", NervesHub.Workers.ScheduleOrgAuditLogTruncation},
       {"*/1 * * * *", NervesHub.Workers.CleanStaleDeviceConnections},
       {"1,16,31,46 * * * *", NervesHub.Workers.DeleteOldDeviceConnections},
       {"*/5 * * * *", NervesHub.Workers.ExpireInflightUpdates},
       {"*/15 * * * *", NervesHub.Workers.DeviceHealthTruncation}
     ]}
  ]

config :nerves_hub, NervesHubWeb.Gettext, default_locale: "en"

config :swoosh, :api_client, Swoosh.ApiClient.Finch

config :flop, repo: NervesHub.Repo

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.2",
  default: [
    args:
      ~w(ui-rework/app.js --bundle --target=es2021 --outdir=../priv/static/assets/ui-rework --external:/fonts/* --external:/images/* --loader:.png=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=ui-rework/app.css
      --output=../priv/static/assets/ui-rework/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile openid"]}
  ]

# Used by spellweaver
config :bun, :version, "1.2.18"

# Environment specific config
import_config "#{Mix.env()}.exs"
