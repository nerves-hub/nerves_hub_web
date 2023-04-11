import Config

# Do not print debug messages in production
config :logger, level: :info

config :phoenix, logger: false

##
# NervesHub API
#
config :nerves_hub, NervesHubWeb.API.Endpoint,
  load_from_system_env: true,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint, server: true

##
# NervesHub
#
config :nerves_hub,
  enable_workers: true,
  firmware_upload: NervesHub.Firmwares.Upload.S3

config :nerves_hub, NervesHub.Mailer,
  adapter: Bamboo.SMTPAdapter,
  tls: :always,
  ssl: false,
  retries: 1

config :nerves_hub, NervesHub.Repo, pool_size: 20

##
# NervesHubWWW
#
config :nerves_hub, NervesHubWeb.Endpoint,
  load_from_system_env: true,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]
