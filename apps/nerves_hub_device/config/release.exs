import Config

logger_level = System.get_env("LOG_LEVEL", "warn") |> String.to_atom()

config :logger, level: logger_level

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.split(" ", trim: true)
      |> Enum.map(&String.to_atom/1)

    :error ->
      []
  end

config :kernel,
  sync_nodes_optional: sync_nodes_optional,
  sync_nodes_timeout: 5000,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9155

if rollbar_access_token = System.get_env("ROLLBAR_ACCESS_TOKEN") do
  config :rollbax, access_token: rollbar_access_token
else
  config :rollbax, enabled: false
end

config :nerves_hub_web_core,
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Workers.FirmwaresTransferS3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint, server: true

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  url: [host: host],
  https:
    [
      port: 443,
      otp_app: :nerves_hub_device,
      # Enable client SSL
      # Older versions of OTP 25 may break using using devices
      # that support TLS 1.3 or 1.2 negotiation. To mitigate that
      # potential error, we enforce TLS 1.2. If you're using OTP >= 25.1
      # on all devices, then it is safe to allow TLS 1.3 by removing
      # the versions constraint and setting `certificate_authorities: false`
      # since we don't expect devices to send full chains to the server
      # See https://github.com/erlang/otp/issues/6492#issuecomment-1323874205
      #
      # certificate_authorities: false,
      versions: [:"tlsv1.2"],
      signature_algs: [
        [
          ## TLS 1.3
          ## Because we're forcing TLS 1.2 for now, these can be excluded
          # :eddsa_ed25519,
          # :eddsa_ed448,
          # :ecdsa_secp521r1_sha512,
          # :ecdsa_secp384r1_sha384,
          # :ecdsa_secp256r1_sha256,
          # :rsa_pss_pss_sha512,
          # :rsa_pss_pss_sha384,
          # :rsa_pss_pss_sha256,
          # :rsa_pss_rsae_sha512,
          # :rsa_pss_rsae_sha384,
          # :rsa_pss_rsae_sha256,

          # TLS 1.2
          {:sha512, :ecdsa},
          :rsa_pss_pss_sha512,
          :rsa_pss_rsae_sha512,
          {:sha512, :rsa},
          {:sha384, :ecdsa},
          :rsa_pss_pss_sha384,
          :rsa_pss_rsae_sha384,
          {:sha384, :rsa},
          {:sha256, :ecdsa},
          :rsa_pss_pss_sha256,
          :rsa_pss_rsae_sha256,
          {:sha256, :rsa}

          # These commonly break with devices using crypto chips for an unknown
          # reason when using OTP >= 25, so we opt to exclude them since they
          # probably are not being used anyway
          #
          # {:sha224, :ecdsa},
          # {:sha224, :rsa},
          # {:sha, :ecdsa},
          # {:sha, :rsa},
          # {:sha, :dsa}
        ]
      ],
      verify: :verify_peer,
      fail_if_no_peer_cert: true,
      keyfile: "/etc/ssl/#{host}-key.pem",
      certfile: "/etc/ssl/#{host}.pem",
      cacertfile: "/etc/ssl/ca.pem"
    ] ++ tls_opts
