import Config

# Do not print debug messages in production
config :logger, level: :info

config :phoenix, logger: false

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint, https: [ip: {0, 0, 0, 0, 0, 0, 0, 0}]

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

##
# NervesHubWWW
#
config :nerves_hub, NervesHubWeb.Endpoint, http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}]
