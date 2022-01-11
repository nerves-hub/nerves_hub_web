# Deploying NervesHub

This document will explain the high level requirements to deploying NervesHub. It will require some intermediate knowledge of at least the following topics:

* setting up linux systems
* configuring linux networks
* using SQL
* famaliararity with Elixir and Mix

I've intentionally not used Docker/Terraform/Kubernetes or other complex deployment tools for simplicity. 

## Table Of Contents

* [Glossary](#Glossary) Commonly used terms that you should know before moving forward
* [Domains](#Domains) Domain names that will need to be configured in your providers DNS settings.
* [Preamble](#Preamble) Beginning of the actual guide

## Glossary

|term |definition                                                       |
|-----|-----------------------------------------------------------------|
| ca  | Certificate Authority                                           |
| pem | Common format for storing SSL certificates                      |
| vm  | linux virtual machine, probably hosted on gcp or aws or similar |

## Domains

There are four domains required to be configured for NervesHub to work. You can use whatever you want, however there is a
"standard" of sorts. Below is a table to help:

| Domain                | OTP Application   | Function                                                                               |
| --------------------- | ----------------- | -------------------------------------------------------------------------------------- |
| nerves-hub.org        | nerves_hub_www    | Provides the primary user interface to NervesHub. Your browser connects to this domain |
| api.nerves-hub.org    | nerves_hub_api    | Provides an HTTP/REST API to NervesHub. the mix commands use this domain               |
| device.nerves-hub.org | nerves_hub_device | Provides a websocket API for decices to connect to                                     |
| ca.nerves-hub.org     | nerves_hub_ca     | Provides a certificate authority for authorizing the api and device domains            |

Please note that you will need to change the `nerves-hub.org` portion of all domains to something you control. 
Another note: the `ca.*` domain, should not be accessable to the general internet. Only the `api.*` and `device.*` domains should be
allowed to access it. 

## Preamble

This guide assumes basic knowledge of how NervesHub works internally. Most notably, the chain of SSL certificates.

## Prerequisites

The NervesHub web app requires several external services to function. 

### SQL

NervesHub and NervesHubCA both require a postgresql connection. The most common method of configuration for
this service is to use the `DATABASE_URL` environment variable.

### Object Storage

NervesHub supports local file storage and remote S3 integration for object storage which is required for storing firmware files. NervesHub uses a [`NervesHubWebCore.Firmwares.Upload`](https://github.com/nerves-hub/nerves_hub_web/blob/next/apps/nerves_hub_web_core/lib/nerves_hub_web_core/firmwares/upload.ex) behavior to define required callbacks if you wish to implement your own.

By default, S3 is assumed and the NervesHub API requires two buckets. One for logging, the other for storing firmware files. Relevent environment variables are:

* `AWS_REGION`
* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`
* `S3_BUCKET_NAME` - firmware file bucket
* `S3_LOG_BUCKET_NAME` - logs

### Email

The NervesHub web application requires an email service to send activity and account activation instructions. 
Relevent environment variables are:

* `SES_SERVER`
* `SES_PORT`
* `SMTP_USERNAME`
* `SMTP_PASSWORD`
* `FROM_EMAIL`

## Getting Started

The very first thing you will need is access to 4 distinct Linux machines. This section is split into 4 parts, each section cooresponding to 
a domain. 

### Common Setup

All four applications and both codebases are Elixir OTP releases. below are some sample common steps that will be required on all 4 machines:

```bash
export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac"
export KERL_BUILD_DOCS="yes"
export ERL_AFLAGS="+pc unicode -kernel shell_history enabled -kernel shell_history_path '\"$HOME/.erl_history\"'"
export MIX_ENV=prod
```

Install apt dependencies:

```bash
sudo apt install nginx \
                 certbot \
                 python-certbot-nginx \
                 git \
                 curl \
                 wget \
                 build-essential \
                 autoconf \
                 m4 \
                 libncurses5-dev \
                 libwxgtk3.0-gtk3-dev \
                 libgl1-mesa-dev \
                 libglu1-mesa-dev \
                 libpng-dev \
                 libssh-dev \
                 unixodbc-dev \
                 xsltproc \
                 fop \
                 libxml2-utils \
                 libncurses-dev \
                 openjdk-11-jdk
```

Install ASDF: 

```bash
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.1
```

Add the following to .bashrc:

```bash
. $HOME/.asdf/asdf.sh
. $HOME/.asdf/completions/asdf.bash
```
Install erlang and elixir plugins

```bash
asdf plugin-add erlang
asdf plugin-add elixir
```

Install erlang and elixir:

```bash
asdf install erlang 24.2
asdf install elixir 1.13.1-otp-24
asdf global erlang 24.2
asdf global elixir 1.13.1-otp-24
```

### ca.nerves-hub.org

(remember to use your own domain name)

First you will need to obtain the source code to build the application:

```bash
git clone https://github.com/nerves-hub/nerves_hub_ca.git
cd nerves_hub_ca
```

Before proceeding, you will need to ensure the following environment variables are 
exported. Make sure you update them to your environment

```bash
export PORT=443
export HOST="ca.nerves-hub.org"
export DATABASE_URL="ecto://username:password@db-host/nerves_hub_ca"
```

Next you need to generate the SSL certificates for the entire stack:

```bash
mix nerves_hub_ca.init --path ssl
```

Next up, you need to configure paths to the various SSL certificates. 
Edit the file called `config/release.exs`: 

```elixir
config :nerves_hub_ca, :api,
  port: 443,
  verify: :verify_peer,
  fail_if_no_peer_cert: true

working_dir = "/home/connor/nerves_hub_ca/ssl"

config :nerves_hub_ca, :api,
  cacertfile: Path.join(working_dir, "ca.pem"),
  certfile: Path.join(working_dir, "ca.keeplabs.com.pem"),
  keyfile: Path.join(working_dir, "ca.keeplabs.com-key.pem")

config :nerves_hub_ca, CA.User,
  ca: Path.join(working_dir, "user-root-ca.pem"),
  ca_key: Path.join(working_dir, "user-root-ca-key.pem")

config :nerves_hub_ca, CA.Device,
  ca: Path.join(working_dir, "device-root-ca.pem"),
  ca_key: Path.join(working_dir, "device-root-ca-key.pem")
```

Next, create and migrate the Postgres database:

```bash
mix ecto.create
mix ecto.migrate
```

Finally, you can generate and execute the release:

```bash
mix release
_build/prod/rel/nerves_hub_ca/bin/nerves_hub_ca start_iex
```

That's it for this service. Open a new terminal and proceed to the next section.

### api.nerves-hub.org

(remember to use your own domain name)

First you will need to obtain the source code to build the application:

```bash
git clone https://github.com/nerves-hub/nerves_hub_web.git
cd nerves_hub_web
```

Before proceding, you will need to ensure the following environment variables are 
exported. Make sure you update them to your environment

```bash
export PORT=4444
export HOST="api.nerves-hub.org"
export DATABASE_URL="ecto://username:password@db-host/nerves_hub_web_prod"
export AWS_REGION="secret"
export AWS_ACCESS_KEY_ID="top secret"
export AWS_SECRET_ACCESS_KEY="top secret"
export S3_BUCKET_NAME="secret"
export S3_LOG_BUCKET_NAME="secret"
export SES_SERVER="smtp.mymailserver.com"
export SES_PORT="587"
export SMTP_USERNAME="apikey"
export SMTP_PASSWORD="top secret"
export FROM_EMAIL="noreply@nerves-hub.org"
export CA_HOST="ca.nerves-hub.org"
```

You will also need a few of the SSL certs that were generated in CA step previously:

* `user-root-ca.pem`
* `root-ca.pem`
* `api.nerves-hub.org-key.pem`
* `api.nerves-hub.org.pem`
* `ca.pem`

First you need to remove references to rollbar. a handy command you can use is:

```bash
find ./apps/ -name \*.ex[s] -print -exec sed -i "/rollbax/d" {} \;
```

Next, you will be binding this service to port 443, which requires root permissions.
You can use iptables to forward the trafic to another port:

```
sudo iptables -t nat -I PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 4444
```

Be warned that using nginx or similar is not possible here due to client side ssl 
certificates. 

Next, open up the file `apps/nerves_hub_api/config/release.exs`:

```elixir
import Config

logger_level = System.get_env("LOG_LEVEL", "warn") |> String.to_atom()

config :logger, level: logger_level

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.trim()
      |> String.split(" ")
      |> Enum.map(&String.to_atom/1)

    :error ->
      []
  end

config :kernel,
  sync_nodes_optional: sync_nodes_optional,
  sync_nodes_timeout: 5000,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9155

config :nerves_hub_web_core,
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Workers.FirmwaresTransferS3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")

config :ex_aws, region: System.fetch_env!("AWS_REGION")

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

cacert_pems = [
  "/path/to/ssl/user-root-ca.pem",
  "/path/to/ssl/root-ca.pem",
]

cacerts =
  cacert_pems
  |> Enum.map(&File.read!/1)
  |> Enum.map(&X509.Certificate.from_pem!/1)
  |> Enum.map(&X509.Certificate.to_der/1)

config :nerves_hub_api, NervesHubAPIWeb.Endpoint,
  url: [host: host],
  https: [
    port: 4444,
    otp_app: :nerves_hub_api,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: "/path/to/ssl/#{host}-key.pem",
    certfile: "/path/to/ssl/#{host}.pem",
    cacerts: cacerts ++ :certifi.cacerts()
  ]

ca_host = System.fetch_env!("CA_HOST")

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: ca_host,
  port: 8443,
  ssl: [
    keyfile: "/path/to/ssl/#{host}-key.pem",
    certfile: "/path/to/ssl/#{host}.pem",
    cacertfile: "/path/to/ssl/ca.pem"
  ]

config :ex_aws,
  region: {:system, "AWS_REGION"},
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

# if using GCP you may want something like:
config :ex_aws, :s3,
  scheme: "https://",
  host: "storage.googleapis.com"
```

Finally, you can generate and execute the release:

```bash
mix release nerves_hub_api
_build/prod/rel/nerves_hub_api/bin/nerves_hub_api start_iex
```

That's it for this service. Open a new terminal and procede to the next section.

### device.nerves-hub.org

(remember to use your own domain name)

First you will need to obtain the source code to build the application:

```bash
git clone https://github.com/nerves-hub/nerves_hub_web.git
cd nerves_hub_web
```

Before proceding, you will need to ensure the following environment variables are 
exported. Make sure you update them to your environment

```bash
export PORT=4444
export HOST="device.nerves-hub.org"
export DATABASE_URL="ecto://username:password@db-host/nerves_hub_web_prod"
export AWS_REGION="secret"
export AWS_ACCESS_KEY_ID="top secret"
export AWS_SECRET_ACCESS_KEY="top secret"
export S3_BUCKET_NAME="secret"
export S3_LOG_BUCKET_NAME="secret"
export SES_SERVER="smtp.mymailserver.com"
export SES_PORT="587"
export SMTP_USERNAME="apikey"
export SMTP_PASSWORD="top secret"
export FROM_EMAIL="noreply@nerves-hub.org"
export CA_HOST="ca.nerves-hub.org"
```

You will also need a few of the SSL certs that were generated in CA step previously:

* `user-root-ca.pem`
* `root-ca.pem`
* `device.nerves-hub.org-key.pem`
* `device.nerves-hub.org.pem`
* `ca.pem`

First you need to remove references to rollbar. a handy command you can use is:

```bash
find ./apps/ -name \*.ex[s] -print -exec sed -i "/rollbax/d" {} \;
```

Next, you will be binding this service to port 443, which requires root permissions.
You can use iptables to forward the trafic to another port:

```
sudo iptables -t nat -I PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 4444
```

Be warned that using nginx or similar is not possible here due to client side ssl 
certificates. 

Next, open up the file `apps/nerves_hub_device/config/release.exs`:

```elixir
import Config

logger_level = System.get_env("LOG_LEVEL", "warn") |> String.to_atom()

config :logger, level: logger_level

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.trim()
      |> String.split(" ")
      |> Enum.map(&String.to_atom/1)

    :error ->
      []
  end

config :kernel,
  sync_nodes_optional: sync_nodes_optional,
  sync_nodes_timeout: 5000,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9155

config :nerves_hub_web_core,
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org")

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Workers.FirmwaresTransferS3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")

config :ex_aws, region: System.fetch_env!("AWS_REGION")

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

host = System.fetch_env!("HOST")

cacert_pems = [
  "/path/to/ssl/user-root-ca.pem",
  "/path/to/ssl/root-ca.pem",
]

cacerts =
  cacert_pems
  |> Enum.map(&File.read!/1)
  |> Enum.map(&X509.Certificate.from_pem!/1)
  |> Enum.map(&X509.Certificate.to_der/1)

config :nerves_hub_device, NervesHubDeviceWeb.Endpoint,
  url: [host: host],
  https: [
    port: 4444,
    otp_app: :nerves_hub_device,
    # Enable client SSL
    verify: :verify_peer,
    keyfile: "/path/to/ssl/#{host}-key.pem",
    certfile: "/path/to/ssl/#{host}.pem",
    cacerts: cacerts ++ :certifi.cacerts()
  ]

ca_host = System.fetch_env!("CA_HOST")

config :nerves_hub_web_core, NervesHubWebCore.CertificateAuthority,
  host: ca_host,
  port: 8443,
  ssl: [
    keyfile: "/path/to/ssl/#{host}-key.pem",
    certfile: "/path/to/ssl/#{host}.pem",
    cacertfile: "/path/to/ssl/ca.pem"
  ]

config :ex_aws,
  region: {:system, "AWS_REGION"},
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

# if using GCP you may want something like:
config :ex_aws, :s3,
  scheme: "https://",
  host: "storage.googleapis.com"
```

Finally, you can generate and execute the release:

```bash
mix release nerves_hub_device
_build/prod/rel/nerves_hub_device/bin/nerves_hub_device start_iex
```

That's it for this service. Open a new terminal and procede to the next section.

### nerves-hub.org

(remember to use your own domain name)

First you will need to obtain the source code to build the application:

```bash
git clone https://github.com/nerves-hub/nerves_hub_web.git
cd nerves_hub_web
```

Before proceding, you will need to ensure the following environment variables are 
exported. Make sure you update them to your environment

```bash
export PORT=4444
export HOST="nerves-hub.org"
export SECRET_KEY_BASE="generate this w/ mix phx.gen.secret"
export LIVE_VIEW_SIGNING_SALT="generate this w/ mix phx.gen.secret"
export DATABASE_URL="ecto://username:password@db-host/nerves_hub_web_prod"
export AWS_REGION="secret"
export AWS_ACCESS_KEY_ID="top secret"
export AWS_SECRET_ACCESS_KEY="top secret"
export S3_BUCKET_NAME="secret"
export S3_LOG_BUCKET_NAME="secret"
export SES_SERVER="smtp.mymailserver.com"
export SES_PORT="587"
export SMTP_USERNAME="apikey"
export SMTP_PASSWORD="top secret"
export FROM_EMAIL="noreply@nerves-hub.org"
```

First you need to remove references to rollbar. a handy command you can use is:

```bash
find ./apps/ -name \*.ex[s] -print -exec sed -i "/rollbax/d" {} \;
``` 

Next, open up the file `apps/nerves_hub_device/config/release.exs`:

```elixir
import Config

logger_level = System.get_env("LOG_LEVEL", "warn") |> String.to_atom()

config :logger, level: logger_level

host = System.fetch_env!("HOST")
port = 80

sync_nodes_optional =
  case System.fetch_env("SYNC_NODES_OPTIONAL") do
    {:ok, sync_nodes_optional} ->
      sync_nodes_optional
      |> String.trim()
      |> String.split(" ")
      |> Enum.map(&String.to_atom/1)

    :error ->
      []
  end

config :kernel,
  sync_nodes_optional: sync_nodes_optional,
  sync_nodes_timeout: 5000,
  inet_dist_listen_min: 9100,
  inet_dist_listen_max: 9155

config :nerves_hub_web_core, NervesHubWebCore.Firmwares.Upload.S3,
  bucket: System.fetch_env!("S3_BUCKET_NAME")

config :nerves_hub_web_core, NervesHubWebCore.Workers.FirmwaresTransferS3Ingress,
  bucket: System.fetch_env!("S3_LOG_BUCKET_NAME")


config :ex_aws,
  region: {:system, "AWS_REGION"},
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

config :ex_aws, :s3,
  scheme: "https://",
  host: "storage.googleapis.com"

config :nerves_hub_www, NervesHubWWWWeb.Endpoint,
  secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
  live_view: [signing_salt: System.fetch_env!("LIVE_VIEW_SIGNING_SALT")]

config :nerves_hub_web_core, NervesHubWebCore.Mailer,
  adapter: Bamboo.SMTPAdapter,
  server: System.fetch_env!("SES_SERVER"),
  port: System.fetch_env!("SES_PORT"),
  username: System.fetch_env!("SMTP_USERNAME"),
  password: System.fetch_env!("SMTP_PASSWORD")

config :nerves_hub_web_core,
  host: host,
  port: port,
  from_email: System.get_env("FROM_EMAIL", "no-reply@nerves-hub.org"),
  allow_signups?: System.get_env("ALLOW_SIGNUPS", "true") |> String.to_atom()

config :nerves_hub_www, NervesHubWWWWeb.Endpoint, url: [host: host, port: port]
```

This server has no special SSL requirements, so you can use nginx if you want. 
This is helpful for managing SSL certificates, but is outside the scope of this
guide. 

Finally, you can generate and execute the release:

```bash
mix release nerves_hub_www
_build/prod/rel/nerves_hub_www/bin/nerves_hub_www start_iex
```

That's it for this service. Open a new terminal and procede to the next section.

## Distribution

NervesHub uses Erlang Distribution to facilitate communication between services for
some features. Setting this up is slightly more complex than the scope of this 
guide. For testing, the following may be sufficient: 

```elixir
# run this on api, device and www:
Node.set_cookie(:democookie)
# run these on www only (the network will propagate)
Node.connect(:"nerves_hub_api@api.nerves-hub.org")
Node.connect(:"nerves_hub_device@device.nerves-hub.org")
```

## Library Configuration

If all went well above, You should be able to access your nerves-hub instance
via web browser. Next to configure is the `cli`.

### nerves_hub_cli

In your firmware project, add new `config.exs` enteries:

```elixir
config :nerves, :firmware, provisioning: :nerves_hub_link

host = "my.nerveshub.domain"
port = 443

config :nerves_hub_link,
  fwup_public_keys: [:devkey]

config :nerves_hub_link,
  device_api_host: "device.#{host}",
  device_api_sni: 'device.nerves-hub.org',
  device_api_port: port,
  ca_store: Firmware.CAStore,
  remote_iex: true

config :nerves_hub_user_api,
  host: "api.#{host}",
  server_name_indication: 'api.nerves-hub.org',
  port: port

config :nerves_hub_user_api, ca_store: Firmware.CAStore
```

And of course the source for that `Firmware.CAStore` module:

```elixir
defmodule Elias.CAStore do
  @moduledoc """
  Certificate Authority Store for the production NervesHub instance
  """

  @doc """
  Returns DER encoded list of CA certificates
  """
  @spec cacerts() :: [:public_key.der_encoded()]
  def cacerts() do
    for cert <- certificates(), do: X509.Certificate.to_der(cert)
  end

  @doc """
  Alias for NervesHubCAStore.cacerts/1
  """
  @spec ca_certs() :: [:public_key.der_encoded()]
  def ca_certs(), do: cacerts()

  @doc """
  CA Store as list of OTP compatible certificate records
  """
  @spec certificates() :: [tuple()]
  def certificates() do
    file_path()
    |> File.read!()
    |> X509.from_pem()
  end

  @doc """
  File path to cacerts.pem
  """
  @spec file_path() :: Path.t()
  def file_path() do
    raise """
    This will need to be configured for real. Simply delete this statement and
    replace it with something that has all the ca certs in it. For example you might
    want something like:


        Application.app_dir(:my_firmware, ["priv", "cacerts.pem"])
    """
  end
end
```