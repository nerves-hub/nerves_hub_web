use Mix.Config

config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  load_from_system_env: true,
  url: [host: "api.nerves-hub.org"],
  server: true,
  https: [
    port: 443,
    otp_app: :nerves_hub_api,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: "/etc/ssl/api.nerves-hub.org-key.pem",
    certfile: "/etc/ssl/api.nerves-hub.org.pem",
    cacertfile: "/etc/ssl/ca.pem"
  ]

# Do not print debug messages in production
config :logger, level: :debug

config :rollbax,
  environment: to_string(Mix.env()),
  enabled: true,
  enable_crash_reports: true
