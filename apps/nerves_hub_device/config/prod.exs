use Mix.Config

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  load_from_system_env: true,
  url: [host: "device.nerves-hub.org"],
  pubsub: [name: NervesHubWWW.PubSub,
           adapter: Phoenix.PubSub.PG2],
  server: true,
  https: [
    port: 443,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: "/etc/ssl/server-key.pem",
    certfile: "/etc/ssl/server.pem",
    cacertfile: "/etc/ssl/ca.pem"
  ]

# Do not print debug messages in production
config :logger, level: :debug
