import Config

# Do not print debug messages in production
config :logger, level: :warn

config :rollbax,
  environment: to_string(Mix.env()),
  enabled: true,
  enable_crash_reports: true

##
# NervesHub API
#
config :nerves_hub_api, NervesHubAPIWeb.Endpoint, server: true

##
# NervesHub Device
#
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint, server: true

##
# NervesHubWebCore
#
config :nerves_hub_web_core,
  firmware_upload: NervesHubWebCore.Firmwares.Upload.S3,
  host: "www.nerves-hub.org",
  port: 80

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  tls: :always,
  ssl: false,
  retries: 1

config :nerves_hub_web_core, NervesHubWebCore.Scheduler,
  jobs: [
    garbage_collect_firmware: [
      schedule: "*/15 * * * *",
      run_strategy: {Quantum.RunStrategy.Random, :cluster},
      task: {NervesHubWebCore.Firmwares.GC, :run, []}
    ],
    digest_firmware_transfers: [
      schedule: "*/30 * * * *",
      run_strategy: {Quantum.RunStrategy.Random, :cluster},
      task: {NervesHubWebCore.Firmwares.Transfer.S3Ingress, :run, []}
    ],
    create_org_metrics: [
      schedule: "0 1 * * *",
      run_strategy: {Quantum.RunStrategy.Random, :cluster},
      task: {NervesHubWebCore.Accounts, :create_org_metrics, ["01:00:00.000000"]}
    ]
  ]

##
# NervesHubWWW
#
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  load_from_system_env: true,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto]]

config :nerves_hub_www, NervesHubWWWWeb.AccountController, allow_signups: false
