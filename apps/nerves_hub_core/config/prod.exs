use Mix.Config

config :nerves_hub_core, NervesHubCore.Repo,
  adapter: Ecto.Adapters.Postgres,
  url: "${DATABASE_URL}"
