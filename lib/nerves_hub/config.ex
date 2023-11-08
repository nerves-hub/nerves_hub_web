defmodule NervesHub.Config do
  use Vapor.Planner

  dotenv()

  config :nerves_hub,
         env([
           {:app, "NERVES_HUB_APP",
            map: fn
              "www" -> "web"
              other -> other
            end},
           {:from_email, "NERVES_HUB_FROM_EMAIL"},
           {:deploy_env, "NERVES_HUB_DEPLOY_ENV"},
           {:firmware_upload_backend, "FIRMWARE_UPLOAD_BACKEND"}
         ])

  config :rate_limit,
         env([
           {:limit, "DEVICE_CONNECT_RATE_LIMIT", default: 100, map: &String.to_integer/1}
         ])

  config :database,
         env([
           {:ipv6, "DATABASE_IPV6", default: false, map: &to_boolean/1},
           {:pool_size, "POOL_SIZE", default: 5, map: &String.to_integer/1},
           {:ssl, "DATABASE_SSL", default: false, map: &to_boolean/1},
           {:url, "DATABASE_URL"}
         ])

  config :web_endpoint,
         env([
           {:live_view_signing_salt, "WEB_ENDPOINT_LIVE_VIEW_SIGNING_SALT", required: false},
           {:secret_key_base, "WEB_ENDPOINT_SECRET_KEY_BASE"},
           {:http_port, "WEB_ENDPOINT_HTTP_PORT", map: &String.to_integer/1},
           {:url_host, "WEB_ENDPOINT_URL_HOST"},
           {:url_port, "WEB_ENDPOINT_URL_PORT", default: 443, map: &String.to_integer/1},
           {:url_scheme, "WEB_ENDPOINT_URL_SCHEME", default: "https"},
           {:server, "WEB_ENDPOINT_SERVER", default: true, map: &to_boolean/1}
         ])

  config :device_endpoint,
         env([
           {:https_port, "DEVICE_ENDPOINT_HTTPS_PORT", map: &String.to_integer/1},
           {:https_keyfile, "DEVICE_ENDPOINT_HTTPS_KEYFILE"},
           {:https_certfile, "DEVICE_ENDPOINT_HTTPS_CERTFILE"},
           {:https_cacertfile, "DEVICE_ENDPOINT_HTTPS_CACERTFILE"},
           {:url_host, "DEVICE_ENDPOINT_URL_HOST"},
           {:url_port, "DEVICE_ENDPOINT_URL_PORT", default: 443, map: &String.to_integer/1},
           {:server, "DEVICE_ENDPOINT_SERVER", default: true, map: &to_boolean/1}
         ])

  config :audit_logs,
         env([
           {:enabled, "TRUNATE_AUDIT_LOGS_ENABLED", default: "false", map: &to_boolean/1},
           {:max_records_per_run, "TRUNCATE_AUDIT_LOGS_MAX_RECORDS_PER_RUN",
            default: 10000, map: &String.to_integer/1},
           {:days_kept, "TRUNCATE_AUDIT_LOGS_MAX_DAYS_KEPT",
            default: 30, map: &String.to_integer/1}
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

  config :sentry,
         env([
           {:dsn_url, "SENTRY_DSN_URL"},
           {:included_environments, "SENTRY_INCLUDED_ENVIRONMENTS",
            default: ["prod"], map: fn envs -> String.split(envs, ",") end}
         ])

  config :libcluster,
         env([
           {:strategy, "LIBCLUSTER_STRATEGY",
            map: fn
              strategy when strategy in ["gossip", "dns_poll"] -> strategy
              strategy -> raise ArgumentError, ~s|unknown libcluster strategy "#{strategy}"|
            end}
         ])

  def to_boolean("true"), do: true
  def to_boolean(_), do: false

  def load! do
    __MODULE__
    |> Vapor.load!()
    |> setup_firmware_upload_backend()
    |> setup_libcluster()
  end

  defp setup_firmware_upload_backend(vapor) do
    case vapor.nerves_hub.firmware_upload_backend do
      "S3" ->
        %{firmware_backend: s3} = Vapor.load!(NervesHub.Config.FirmwareBackendS3)

        Application.put_env(:ex_aws, :access_key_id, [s3.access_key_id, :instance_role])
        Application.put_env(:ex_aws, :secret_access_key, [s3.secret_access_key, :instance_role])
        Application.put_env(:ex_aws, :region, s3.region)

        Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.S3, bucket: s3.bucket)

      "local" ->
        %{firmware_backend: file} = Vapor.load!(NervesHub.Config.FirmwareBackendFile)

        Application.put_env(:nerves_hub, NervesHub.Firmwares.Upload.File,
          enabled: true,
          local_path: file.local_path,
          public_path: file.public_path
        )
    end

    vapor
  end

  defp setup_libcluster(vapor) do
    put_in(
      vapor,
      [:libcluster, :topologies],
      setup_libcluster_topologies(vapor.libcluster.strategy)
    )
  end

  defp setup_libcluster_topologies("gossip") do
    [gossip: [strategy: Cluster.Strategy.Gossip]]
  end

  defp setup_libcluster_topologies("dns_poll") do
    %{dns_poll: dns} = Vapor.load!(NervesHub.Config.DNSPoll)

    [
      dns_poll: [
        strategy: Cluster.Strategy.DNSPoll,
        config: Map.to_list(dns)
      ]
    ]
  end
end
