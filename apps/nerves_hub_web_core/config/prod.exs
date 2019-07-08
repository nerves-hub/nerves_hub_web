use Mix.Config

config :nerves_hub_web_core, NervesHubWebCore.Scheduler,
  global: true,
  jobs: [
    garbage_collect_firmware: [
      schedule: "*/15 * * * *",
      task: {NervesHubWebCore.Firmwares.GC, :run, []}
    ],
    digest_firmware_transfers: [
      schedule: "*/30 * * * *",
      task: {NervesHubWebCore.Firmwares.Transfer.S3Ingress, :run, []}
    ],
    create_org_metrics: [
      schedule: "0 1 * * *",
      task: {NervesHubWebCore.Accounts, :create_org_metrics, ["01:00:00.000000", [days: -1]]}
    ]
  ]

config :nerves_hub_web_core, firmware_upload: NervesHubWebCore.Firmwares.Upload.S3

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: "nerves-hub-ca.local",
  port: 8443,
  ssl: [
    keyfile: "/etc/ssl/ca-client-key.pem",
    certfile: "/etc/ssl/ca-client.pem",
    cacertfile: "/etc/ssl/ca.pem",
    server_name_indication: 'ca.nerves-hub.org'
  ]
