# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :nerves_hub_core,
  ecto_repos: [NervesHubCore.Repo]

config :nerves_hub_core, NervesHubWeb.PubSub,
  name: NervesHubWeb.PubSub,
  adapter: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

import_config "#{Mix.env()}.exs"
