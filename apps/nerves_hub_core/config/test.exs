use Mix.Config

config :nerves_hub_core, NervesHubCore.Repo,
  adapter: Ecto.Adapters.Postgres,
  ssl: false,
  pool: Ecto.Adapters.SQL.Sandbox
