use Mix.Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [yarn: ["run", "watch", cd: Path.expand("../assets", __DIR__)]]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# command from your terminal:
#
#     openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com" -keyout priv/server.key -out priv/server.pem
#
# The `http:` config above can be replaced with:
#
#     https: [port: 4000, keyfile: "priv/server.key", certfile: "priv/server.pem"],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  url: [scheme: "http", host: "0.0.0.0", port: 4000],
  live_reload: [
    patterns: [
      ~r{priv/static/js/.*(js)$},
      ~r{priv/static/css/.*(css)$},
      ~r{priv/static/images/.*(png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/nerves_hub_www_web/views/.*(ex)$},
      ~r{lib/nerves_hub_www_web/templates/.*(eex|haml|md)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# uncomment if using NervesHubCore.Firmwares.Upload.File
# config :nerves_hub_www, firmware_upload: NervesHubCore.Firmwares.Upload.File

# uncomment out lines 19-23 in endpoint.ex and update paths accordingly
# config :nerves_hub_www, NervesHubCore.Firmwares.Upload.File,
#   local_path: "/tmp/firmware",
#   public_path: "/firmware"

# if using NervesHubCore.Firmwares.Upload.S3, set configuration below accordingly
config :nerves_hub_www, firmware_upload: NervesHubCore.Firmwares.Upload.File

config :nerves_hub_www, NervesHubCore.Firmwares.Upload.File,
  local_path: "/Users/steve/firmware",
  public_path: "/firmware"

# config :nerves_hub_www, NervesHubCore.Firmwares.Upload.S3, bucket: System.get_env("S3_BUCKET_NAME")

config :nerves_hub_www, NervesHubCore.CertificateAuthority,
  host: "0.0.0.0",
  port: 8443,
  ssl: [
    keyfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca-client-key.pem"]),
    certfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca-client.pem"]),
    cacertfile: Path.join([__DIR__, "../../../test/fixtures/cfssl/ca.pem"]),
    server_name_indication: 'ca.nerves-hub.org'
  ]


config :nerves_hub_www, NervesHubWWW.Mailer, adapter: Bamboo.LocalAdapter
