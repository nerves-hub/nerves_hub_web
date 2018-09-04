# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :nerves_hub_core,
  ecto_repos: [NervesHubCore.Repo],
  product_firmware_limit: 5

config :nerves_hub_core, NervesHubWeb.PubSub,
  name: NervesHubWeb.PubSub,
  adapter: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION")

import_config "#{Mix.env()}.exs"
