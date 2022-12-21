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

# OTP 25.2 includes SSL 10.8.6 which allows disabling certificate authorities
# check with Client SSL since we don't expect devices to send full chains
# up to NervesHub. This allows the use of TLS 1.3
ssl_ver = to_string(Application.spec(:ssl)[:vsn])

tlsv1_2_signature_algs = [
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

tls_opts =
  if Version.match?(ssl_ver, ">= 10.8.6") do
    [
      certificate_authorities: false,
      signature_algs: [
        :eddsa_ed25519,
        :eddsa_ed448,
        :ecdsa_secp521r1_sha512,
        :ecdsa_secp384r1_sha384,
        :ecdsa_secp256r1_sha256,
        :rsa_pss_pss_sha512,
        :rsa_pss_pss_sha384,
        :rsa_pss_pss_sha256,
        :rsa_pss_rsae_sha512,
        :rsa_pss_rsae_sha384,
        :rsa_pss_rsae_sha256 | tlsv1_2_signature_algs
      ]
    ]
  else
    [versions: [:"tlsv1.2"], signature_algs: tlsv1_2_signature_algs]
  end

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  url: [host: host],
  https:
    [
      port: 443,
      otp_app: :nerves_hub_device,
      # Enable client SSL
      verify: :verify_peer,
      fail_if_no_peer_cert: true,
      keyfile: "/etc/ssl/#{host}-key.pem",
      certfile: "/etc/ssl/#{host}.pem",
      cacertfile: "/etc/ssl/ca.pem"
    ] ++ tls_opts
