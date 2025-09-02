import Config

# Do not print debug messages in production
config :logger, level: :info, backends: [:console, Sentry.LoggerBackend]

config :nerves_hub, NervesHub.ObanRepo, pool_size: 10
config :nerves_hub, NervesHub.Repo, pool_size: 20
config :nerves_hub, NervesHubWeb.DeviceEndpoint, server: true

config :nerves_hub, NervesHubWeb.Endpoint,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :phoenix, logger: false
