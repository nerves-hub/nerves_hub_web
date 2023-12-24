import Config

# Do not print debug messages in production
config :logger, level: :info, backends: [:console, Sentry.LoggerBackend]

config :phoenix, logger: false

##
# NervesHub Web
#
config :nerves_hub, NervesHubWeb.Endpoint,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint, server: true

##
# Database and Oban
#
config :nerves_hub, NervesHub.Repo,
  ssl: true,
  pool_size: 20

config :nerves_hub, NervesHub.ObanRepo,
  ssl: true,
  pool_size: 10
