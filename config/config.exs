import Config

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata level=$level $message\n",
  metadata: [:user_id, :request_id, :trace_id, :span_id]

config :phoenix,
  json_library: Jason,
  template_engines: [
    md: PhoenixMarkdown.Engine,
    leex: Phoenix.LiveView.Engine
  ]

##
# NervesHub Device
#

# Configures the endpoint
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub
#
config :nerves_hub,
  env: Mix.env(),
  namespace: NervesHub,
  ecto_repos: [NervesHub.Repo]

config :nerves_hub, Oban,
  repo: NervesHub.ObanRepo,
  log: false,
  queues: [delete_firmware: 1, firmware_delta_builder: 2, truncate: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", NervesHub.Workers.TruncateAuditLogs, max_attempts: 1},
       {"*/5 * * * *", NervesHub.Workers.ExpireInflightUpdates}
     ]}
  ]

config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000

##
# NervesHubWWW
#
config :nerves_hub,
  ecto_repos: [NervesHub.Repo],
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl]

config :nerves_hub, NervesHubWeb.Gettext, default_locale: "en"

# Configures the endpoint
config :nerves_hub, NervesHubWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "ZH9GG2S5CwIMWXBg92wUuoyKFrjgqaAybHLTLuUk1xZO0HeidcJbnMBSTHDcyhSn",
  live_view: [
    signing_salt: "Kct3W8U7uQ6KAczYjzNbiYS6A8Pbtk3f"
  ],
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource: %{service: %{name: "nerves_hub"}}

config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Environment specific config
import_config "#{Mix.env()}.exs"
