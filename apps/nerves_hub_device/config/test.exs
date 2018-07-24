use Mix.Config

config :nerves_hub_device,
  device_serial_header: "x-client-dn",
  websocket_auth_methods: [:ssl, :header]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  pubsub: [name: NervesHubWeb.PubSub, adapter: Phoenix.PubSub.PG2],
  https: [
    port: 4443,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: Path.join([__DIR__ ,"../../../test/fixtures/cfssl/server-key.pem"]),
    certfile: Path.join([__DIR__ ,"../../../test/fixtures/cfssl/server.pem"]),
    cacertfile: Path.join([__DIR__ ,"../../../test/fixtures/cfssl/ca.pem"])
  ]
# Print only warnings and errors during test
config :logger, level: :warn
