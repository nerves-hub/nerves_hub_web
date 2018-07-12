# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :nerves_hub,
  ecto_repos: [NervesHubCore.Repo],
  # Options are :ssl or :header
  websocket_auth_methods: [:ssl]

# Configures the endpoint
config :nerves_hub, NervesHubWeb.Endpoint,
  url: [host: System.get_env("HOST")],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: NervesHub.PubSub]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :nerves_hub, NervesHub.Mailer, adapter: Swoosh.Adapters.Local

config :nerves_hub, NervesHubWeb.AccountController, allow_signups: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
