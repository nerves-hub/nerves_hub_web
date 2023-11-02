import Config

logger_level = System.get_env("LOG_LEVEL", "info") |> String.to_atom()

config :logger, level: logger_level

config :nerves_hub, NervesHub.SwooshMailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD"),
  ssl: false,
  tls: :always,
  retries: 1

config :sentry,
  dsn: System.get_env("SENTRY_DSN_URL"),
  environment_name: System.get_env("NERVES_HUB_DEPLOY_ENV")
