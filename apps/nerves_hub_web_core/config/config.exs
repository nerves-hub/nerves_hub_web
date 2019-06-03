# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :nerves_hub_web_core,
  ecto_repos: [NervesHubWebCore.Repo]

config :nerves_hub_web_core, NervesHubWeb.PubSub,
  name: NervesHubWeb.PubSub,
  adapter: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  json_codec: Jason,
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: System.get_env("AWS_REGION")

config :ex_aws_s3, json_codec: Jason

import_config "#{Mix.env()}.exs"
