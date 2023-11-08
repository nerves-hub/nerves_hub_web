import Config

config :bcrypt_elixir, log_rounds: 4

config :logger, :default_handler, false

##
# NervesHub Device
#
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: []

##
# NervesHub
#
config :nerves_hub, firmware_upload: NervesHub.UploadMock

config :nerves_hub,
  delta_updater: NervesHub.DeltaUpdaterMock

config :nerves_hub, NervesHub.Repo, pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub, NervesHub.ObanRepo, pool: Ecto.Adapters.SQL.Sandbox

config :nerves_hub, NervesHub.SwooshMailer, adapter: Swoosh.Adapters.Test

config :nerves_hub, Oban, queues: false, plugins: false

config :opentelemetry, traces_exporter: :none
