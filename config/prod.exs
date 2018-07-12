use Mix.Config

# For production, we often load configuration from external
# sources, such as your system environment. For this reason,
# you won't find the :http configuration below, but set inside
# NervesHubWeb.Endpoint.init/2 when load_from_system_env is
# true. Any dynamic configuration should be done there.
#
# Don't forget to configure the url host to something meaningful,
# Phoenix uses this information when generating URLs.
#
# Finally, we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the mix phx.digest task
# which you typically run after static files are built.
config :nerves_hub, NervesHubWeb.Endpoint,
  load_from_system_env: true,
  server: true,
  url: [host: "www.nerves-hub.org", port: 80],
  secret_key_base: "${SECRET_KEY_BASE}",
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  cache_static_manifest: "priv/static/cache_manifest.json"

# https: [
#   port: 443,
#   otp_app: :nerves_hub,
#   # Enable client SSL
#   verify: :verify_peer,
#   keyfile: "/etc/ssl/server-key.pem",
#   certfile: "/etc/ssl/server.pem",
#   cacertfile: "/etc/ssl/ca.pem"
# ]

config :nerves_hub, NervesHubWeb.AccountController, allow_signups: false

# Do not print debug messages in production
config :logger, level: :debug

# Configure your database
config :nerves_hub, NervesHub.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: "${DATABASE_URL}"

# should be configured for production

# config :nerves_hub, NervesHub.Mailer, adapter: Swoosh.Adapters.Local
