import Config

# Do not print debug messages in production
config :logger, level: :info

config :nerves_hub, NervesHub.Repo, pool_size: 20
config :nerves_hub, NervesHubWeb.DeviceEndpoint, server: true

config :nerves_hub, NervesHubWeb.Endpoint,
  server: true

config :phoenix, logger: false
