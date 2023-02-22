import Config

# Do not print debug messages in production
config :logger, level: :info

config :phoenix, logger: false

##
# NervesHub API
#
config :nerves_hub_www, NervesHubAPIWeb.Endpoint, server: true

##
# NervesHub Device
#
config :nerves_hub_www, NervesHubDeviceWeb.Endpoint, server: true

##
# NervesHubWebCore
#
config :nerves_hub_www,
  enable_workers: true,
  firmware_upload: NervesHubWebCore.Firmwares.Upload.S3,
  host: "www.nerves-hub.org",
  port: 80

config :nerves_hub_www, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  tls: :always,
  ssl: false,
  retries: 1

config :nerves_hub_www, NervesHubWebCore.Repo, pool_size: 20

##
# NervesHubWWW
#
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  load_from_system_env: true,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]
