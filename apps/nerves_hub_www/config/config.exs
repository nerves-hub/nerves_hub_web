# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :nerves_hub_www,
  ecto_repos: [NervesHubWebCore.Repo],
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl]

config :nerves_hub_www, NervesHubWWWWeb.Gettext, default_locale: "en"

# Configures the endpoint
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  url: [host: System.get_env("HOST")],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: NervesHubWWWWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: NervesHubWeb.PubSub],
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SIGNING_SALT")]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :nerves_hub_www, NervesHubWWW.Mailer, adapter: Bamboo.LocalAdapter

config :nerves_hub_www, NervesHubWWWWeb.AccountController, allow_signups: true

config :phoenix, :json_library, Jason

config :phoenix, :template_engines,
  md: PhoenixMarkdown.Engine,
  leex: Phoenix.LiveView.Engine

config :rollbax, enabled: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
