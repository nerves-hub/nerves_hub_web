# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :nerves_hub_api,
  namespace: NervesHubAPI,
  ecto_repos: [NervesHubWebCore.Repo]

# Configures the endpoint
config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: NervesHubAPIWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: NervesHubWeb.PubSub]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

config :rollbax, enabled: false
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
