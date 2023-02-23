import Config

# Do not print debug messages in production
config :logger, level: :info

config :phoenix, logger: false

##
# NervesHub API
#
config :nerves_hub_www, NervesHubWeb.API.Endpoint, server: true

##
# NervesHub Device
#
config :nerves_hub_www, NervesHubWeb.DeviceEndpoint, server: true

##
# NervesHub
#
config :nerves_hub_www,
  enable_workers: true,
  firmware_upload: NervesHub.Firmwares.Upload.S3,
  host: "www.nerves-hub.org",
  port: 80

config :nerves_hub_www, NervesHub.Mailer,
  adapter: Bamboo.SMTPAdapter,
  tls: :always,
  ssl: false,
  retries: 1

config :nerves_hub_www, NervesHub.Repo, pool_size: 20

##
# NervesHubWWW
#
config :nerves_hub_www, NervesHubWeb.Endpoint,
  load_from_system_env: true,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]
