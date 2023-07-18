import Config

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  json_codec: Jason,
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION")

config :ex_aws_s3, json_codec: Jason

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
# NervesHub API
#

# Configures the endpoint
config :nerves_hub, NervesHubWeb.API.Endpoint,
  render_errors: [view: NervesHubWeb.API.ErrorView, accepts: ~w(json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub Device
#

# Configures the endpoint
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub
#
config :nerves_hub,
  env: Mix.env(),
  namespace: NervesHub,
  ecto_repos: [NervesHub.Repo],
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub, NervesHub.PubSub,
  name: NervesHub.PubSub,
  adapter_name: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

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
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource: %{service: %{name: "nerves_hub"}}

# Environment specific config
import_config "#{Mix.env()}.exs"
