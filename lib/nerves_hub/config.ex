defmodule NervesHub.Config do
  use Vapor.Planner

  dotenv()

  config :database,
         env([
           {:url, "DATABASE_URL"},
           {:pool_size, "POOL_SIZE", default: 5, map: &String.to_integer/1}
         ])

  config :web_endpoint,
         env([
           {:live_view_signing_salt, "LIVE_VIEW_SIGNING_SALT", required: false},
           {:secret_key_base, "SECRET_KEY_BASE"},
           {:url_host, "HOST"},
           {:url_port, "URL_PORT", default: "443", map: &String.to_integer/1},
           {:url_scheme, "URL_SCHEME", default: "https"}
         ])

  config :audit_logs,
         env([
           {:enabled, "TRUNATE_AUDIT_LOGS_ENABLED", default: "false", map: &to_boolean/1},
           {:max_records_per_run, "TRUNCATE_AUDIT_LOGS_MAX_RECORDS_PER_RUN",
            default: "10000", map: &String.to_integer/1},
           {:days_kept, "TRUNCATE_AUDIT_LOGS_MAX_DAYS_KEPT",
            default: "30", map: &String.to_integer/1}
         ])

  config :socket_drano,
         env([
           {:percentage, "SOCKET_DRAIN_BATCH_PERCENTAGE", default: 25, map: &String.to_integer/1},
           {:time, "SOCKET_DRAIN_BATCH_TIME", default: 100, map: &String.to_integer/1}
         ])

  config :statsd,
         env([
           {:host, "STATSD_HOST", default: "localhost"},
           {:port, "STATSD_PORT", default: 8125, map: &String.to_integer/1}
         ])

  def to_boolean("true"), do: true

  def to_boolean(_), do: false
end
