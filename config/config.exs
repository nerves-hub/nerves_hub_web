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
# config :nerves_hub_api,
#  namespace: NervesHubAPI,
#  ecto_repos: [NervesHub.Repo]

# Configures the endpoint
config :nerves_hub_www, NervesHubWeb.API.Endpoint,
  render_errors: [view: NervesHubWeb.API.ErrorView, accepts: ~w(json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub Device
#
# General application configuration
# config :nerves_hub_device,
#   ecto_repos: [NervesHub.Repo],
#   namespace: NervesHubDevice

# Configures the endpoint
config :nerves_hub_www, NervesHubWeb.DeviceEndpoint,
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub
#
config :nerves_hub_www,
  allow_signups?: false,
  ecto_repos: [NervesHub.Repo],
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub_www, NervesHub.PubSub,
  name: NervesHub.PubSub,
  adapter_name: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

config :nerves_hub_www, Oban,
  repo: NervesHub.Repo,
  log: false,
  queues: [delete_firmware: 1, firmware_delta_builder: 2]

config :spandex_phoenix, tracer: NervesHub.Tracer

config :spandex, :decorators, tracer: NervesHub.Tracer

config :nerves_hub_www,
  datadog_host: System.get_env("DATADOG_HOST") || "localhost",
  datadog_port: System.get_env("DATADOG_PORT") || "8126",
  datadog_batch_size: System.get_env("SPANDEX_BATCH_SIZE") || "100",
  datadog_sync_threshold: System.get_env("SPANDEX_SYNC_THRESHOLD") || "100"

config :nerves_hub_www,
  statsd_host: System.get_env("STATSD_HOST", "localhost"),
  statsd_port: System.get_env("STATSD_PORT", "8125")

config :nerves_hub_www, NervesHub.Tracer,
  service: :nerves_hub_www,
  adapter: SpandexDatadog.Adapter,
  disabled?: false,
  type: :web

config :spandex_ecto, SpandexEcto.EctoLogger,
  service: :nerves_hub_www,
  tracer: NervesHub.Tracer,
  otp_app: :nerves_hub_www

##
# NervesHubWWW
#
config :nerves_hub_www,
  ecto_repos: [NervesHub.Repo],
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl]

config :nerves_hub_www, NervesHubWeb.Gettext, default_locale: "en"

# Configures the endpoint
config :nerves_hub_www, NervesHubWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

config :gproc, :gproc_dist, :all

# Environment specific config
import_config "#{Mix.env()}.exs"
