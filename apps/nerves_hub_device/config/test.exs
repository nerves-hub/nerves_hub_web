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
    port: 4101,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    verify_fun: {&NervesHubDevice.SSL.verify_fun/3, nil},
    fail_if_no_peer_cert: true,
    keyfile: Path.join([__DIR__, "../../../test/fixtures/ssl/device.nerves-hub.org-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/ssl/device.nerves-hub.org.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/ssl/ca.pem"])
  ]

# Print only warnings and errors during test
config :logger, level: :debug
