import Config

host = System.get_env("HOST")

config :ex_aws,
  region: {:system, "AWS_REGION"}

config :ex_aws_s3, json_codec: Jason

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

config :phoenix,
  json_library: Jason,
  template_engines: [
    md: PhoenixMarkdown.Engine,
    leex: Phoenix.LiveView.Engine
  ]

config :rollbax, enabled: false

##
# NervesHub API
#
config :nerves_hub_api,
  namespace: NervesHubAPI,
  ecto_repos: [NervesHubWebCore.Repo]

# Configures the endpoint
config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: NervesHubAPIWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: NervesHubWeb.PubSub

##
# NervesHub Device
#
# General application configuration
config :nerves_hub_device,
  ecto_repos: [NervesHubWebCore.Repo],
  namespace: NervesHubDevice

# Configures the endpoint
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  render_errors: [view: NervesHubWWWWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHubWeb.PubSub

##
# NervesHubWebCore
#
config :nerves_hub_web_core,
  allow_signups?: true,
  ecto_repos: [NervesHubWebCore.Repo],
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org"),
  host: host

config :nerves_hub_web_core, NervesHubWeb.PubSub,
  name: NervesHubWeb.PubSub,
  adapter_name: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

config :nerves_hub_web_core, Oban,
  repo: NervesHubWebCore.Repo,
  log: false,
  queues: [delete_firmware: 1]

##
# NervesHubWWW
#
config :nerves_hub_www,
  ecto_repos: [NervesHubWebCore.Repo],
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl]

config :nerves_hub_www, NervesHubWWWWeb.Gettext, default_locale: "en"

# Configures the endpoint
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  url: [host: host],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: NervesHubWWWWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHubWeb.PubSub,
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SIGNING_SALT")]

# Environment specific config
import_config "#{Mix.env()}.exs"
