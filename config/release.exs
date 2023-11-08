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

if token = System.get_env("HONEYCOMB_API_KEY") do
  config :opentelemetry,
    span_processor: :batch,
    exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: "https://api.honeycomb.io:443",
    otlp_headers: [
      {"x-honeycomb-team", token},
      {"x-honeycomb-dataset", System.fetch_env!("FLY_APP_NAME")}
    ]
else
  config :opentelemetry, traces_exporter: :none
end

if token = System.get_env("LIGHTSTEP_ACCESS_TOKEN") do
  config :opentelemetry,
    span_processor: :batch,
    exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_traces_endpoint: "https://ingest.lightstep.com:443/traces/otlp/v0.9",
    otlp_compression: :gzip,
    otlp_headers: [
      {"lightstep-access-token", token}
    ]
else
  config :opentelemetry, traces_exporter: :none
end
