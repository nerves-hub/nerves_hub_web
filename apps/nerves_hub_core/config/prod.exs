use Mix.Config

config :nerves_hub_core, NervesHubCore.Repo, adapter: Ecto.Adapters.Postgres

config :nerves_hub_core, NervesHubCore.CertificateAuthority,
  host: "nerves-hub-ca.local",
  port: 8443,
  ssl: [
    keyfile: "/etc/cfssl/ca-client-key.pem",
    certfile: "/etc/cfssl/ca-client.pem",
    cacertfile: "/etc/cfssl/ca.pem",
    server_name_indication: 'ca.nerves-hub.org',
    verify: :verify_peer
  ]
