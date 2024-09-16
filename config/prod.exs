import Config

# Do not print debug messages in production
config :logger, level: :info, backends: [:console, Sentry.LoggerBackend]

config :phoenix, logger: false

##
# NervesHub Web
#
config :nerves_hub, NervesHubWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  server: true

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  server: true

##
# NervesHub Metrics
#
config :nerves_hub, NervesHubWeb.MetricsEndpoint, server: true

##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo, pool_size: 20

config :nerves_hub, NervesHub.ObanRepo, pool_size: 10
