import Config

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: {NervesHub.LoggerFormatter, :format},
  metadata: :all

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
  ecto_repos: [NervesHub.Repo]

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
config :nerves_hub, NervesHubWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "ZH9GG2S5CwIMWXBg92wUuoyKFrjgqaAybHLTLuUk1xZO0HeidcJbnMBSTHDcyhSn",
  live_view: [
    signing_salt: "Kct3W8U7uQ6KAczYjzNbiYS6A8Pbtk3f"
  ],
  render_errors: [
    formats: [html: NervesHubWeb.ErrorView, json: NervesHubWeb.API.ErrorView],
    accepts: ~w(html json)
  ],
  pubsub_server: NervesHub.PubSub

##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000,
  migration_lock: :pg_advisory_lock

config :nerves_hub, Oban,
  repo: NervesHub.ObanRepo,
  log: false,
  queues: [
    delete_archive: 1,
    delete_firmware: 1,
    device: 1,
    device_deployment_calculations: 5,
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
       {"0 * * * *", NervesHub.Workers.ScheduleOrgAuditLogTruncation, max_attempts: 1},
       {"*/1 * * * *", NervesHub.Workers.CleanDeviceConnectionStates},
       {"*/5 * * * *", NervesHub.Workers.ExpireInflightUpdates},
       {"*/15 * * * *", NervesHub.Workers.DeviceHealthTruncation}
     ]}
  ]

config :nerves_hub, NervesHubWeb.Gettext, default_locale: "en"

config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Environment specific config
import_config "#{Mix.env()}.exs"
