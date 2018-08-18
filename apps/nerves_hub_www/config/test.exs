use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  http: [port: 4001],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :nerves_hub_www, NervesHubWWW.Mailer, adapter: Bamboo.TestAdapter
