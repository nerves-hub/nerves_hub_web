import Config

config :ex_aws, json_codec: Jason

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata level=$level $message\n",
  metadata: [:user_id, :request_id, :trace_id, :span_id]

config :phoenix,
  json_library: Jason,
  template_engines: [
    md: PhoenixMarkdown.Engine,
    leex: Phoenix.LiveView.Engine
  ]

##
# NervesHub Device
#

# Configures the DeviceEndpoint
config :nerves_hub, NervesHubWeb.DeviceEndpoint,
  url: [],
  http: false,
  https: [
    ip: {0, 0, 0, 0},
    otp_app: :nerves_hub,
    # Enable client SSL
    # Older versions of OTP 25 may break using using devices
    # that support TLS 1.3 or 1.2 negotiation. To mitigate that
    # potential error, we enforce TLS 1.2. If you're using OTP >= 25.1
    # on all devices, then it is safe to allow TLS 1.3 by removing
    # the versions constraint and setting `certificate_authorities: false`
    # See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
    #
    # certificate_authorities: false,
    versions: [:"tlsv1.2"],
    verify: :verify_peer,
    verify_fun: {&NervesHub.SSL.verify_fun/3, nil},
    fail_if_no_peer_cert: true
  ],
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

##
# NervesHub
#
config :nerves_hub,
  env: Mix.env(),
  namespace: NervesHub,
  ecto_repos: [NervesHub.Repo]

config :nerves_hub, NervesHub.PubSub,
  name: NervesHub.PubSub,
  adapter_name: Phoenix.PubSub.PG2,
  fastlane: Phoenix.Channel.Server

config :nerves_hub, Oban,
  repo: NervesHub.ObanRepo,
  log: false,
  queues: [delete_firmware: 1, firmware_delta_builder: 2, truncate: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", NervesHub.Workers.TruncateAuditLogs, max_attempts: 1},
       {"*/5 * * * *", NervesHub.Workers.ExpireInflightUpdates}
     ]}
  ]

config :nerves_hub, firmware_upload: NervesHub.Firmwares.Upload.File

config :nerves_hub, NervesHub.Repo,
  queue_target: 500,
  queue_interval: 5_000

##
# NervesHubWWW
#
config :nerves_hub, NervesHubWeb.Gettext, default_locale: "en"

# Configures the Endpoint
config :nerves_hub, NervesHubWeb.Endpoint,
  url: [],
  http: [ip: {0, 0, 0, 0}],
  render_errors: [view: NervesHubWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: NervesHub.PubSub

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource: %{service: %{name: "nerves_hub"}}

config :swoosh, :api_client, Swoosh.ApiClient.Finch

config :sentry,
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  included_environments: ["prod", "production", "staging", "qa"]

# Environment specific config
import_config "#{Mix.env()}.exs"
