import Config

# Do not print debug messages in production
config :logger, level: :info, backends: [:console, Sentry.LoggerBackend]

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
firmware_upload = System.get_env("FIRMWARE_UPLOAD_BACKEND", "S3")

case firmware_upload do
  "S3" ->
    config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.S3

  "local" ->
    config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File
end

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
