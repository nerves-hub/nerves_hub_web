defmodule NervesHub.Config do
  use Vapor.Planner

  dotenv()

  config :database,
         env([
           {:url, "DATABASE_URL"},
           {:pool_size, "POOL_SIZE", default: 5, map: &String.to_integer/1}
         ])

  config :api_endpoint,
         env([
           {:secret_key_base, "SECRET_KEY_BASE"},
           {:url_host, "HOST"},
           {:url_port, "URL_PORT", default: "443", map: &String.to_integer/1},
           {:url_scheme, "URL_SCHEME", default: "https"}
         ])

  config :web_endpoint,
         env([
           {:live_view_signing_salt, "LIVE_VIEW_SIGNING_SALT", required: false},
           {:secret_key_base, "SECRET_KEY_BASE"},
           {:url_host, "HOST"},
           {:url_port, "URL_PORT", default: "443", map: &String.to_integer/1},
           {:url_scheme, "URL_SCHEME", default: "https"}
         ])
end
