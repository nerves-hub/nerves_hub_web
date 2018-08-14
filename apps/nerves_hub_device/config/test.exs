use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  code_reloader: false,
  debug_errors: true,
  check_origin: false,
  watchers: [],
  server: true,
  https: [
    port: 4001,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/device.nerves-hub.org-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/device.nerves-hub.org.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca.pem"])
  ]

# Print only warnings and errors during test
config :logger, level: :debug
