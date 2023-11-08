import Config

config :logger, level: String.to_atom(System.get_env("LOG_LEVEL", "info"))

config :nerves_hub, NervesHub.SwooshMailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD"),
  ssl: false,
  tls: :always,
  retries: 1
