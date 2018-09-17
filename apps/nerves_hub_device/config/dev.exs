use Mix.Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  debug_errors: true,
  code_reloader: false,
  check_origin: false,
  watchers: [],
  https: [
    ip: {0, 0, 0, 0},
    port: 4001,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: Path.expand("./test/fixtures/cfssl/device.nerves-hub.org-key.pem"),
    certfile: Path.expand("./test/fixtures/cfssl/device.nerves-hub.org.pem"),
    cacertfile: Path.expand("./test/fixtures/cfssl/ca.pem")
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20
