# nerves_hub_www

[![CircleCI](https://circleci.com/gh/nerves-hub/nerves_hub_web.svg?style=svg)](https://circleci.com/gh/nerves-hub/nerves_hub_web)
[![Coverage Status](https://coveralls.io/repos/github/nerves-hub/nerves_hub_web/badge.svg?branch=master)](https://coveralls.io/github/nerves-hub/nerves_hub_web?branch=master)

A domain independent back end solution for rolling out software updates to edge
devices connected to IP based networking infrastructure.

## This project is not ready for general use

If you are interested in collaborating. please inquire on the `#nerves-dev`
channel on the [elixir-lang slack](https://elixir-slackin.herokuapp.com/) for
the time being.  We're in the process of building out main features and getting
the project into a form where it can be used and maintained by multiple
companies.

## Project overview and setup

### Development environment setup

If you haven't already, make sure that your development environment has
Elixir 1.7, Erlang 21, and NodeJS.

Here are steps for the NodeJS setup if you're using `asdf`:

```sh
asdf plugin-install nodejs
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring
asdf install nodejs 8.11.3
asdf global nodejs 8.11.3
npm install -g yarn
asdf reshim nodejs 8.11.3
```

On Debian/Ubuntu, you will also need to install the following packages:

```sh
sudo apt install docker-compose inotify-tools
```

Local development uses the host `nerves-hub.org` for connections and cert validation. To properly map to your local running server, you'll need to add a host record for it:

```sh
echo "127.0.0.1 nerves-hub.org" | sudo tee -a /etc/hosts
```

### First time application setup

1. Create directory for local data storage: `mkdir ~/db`
2. Start the database (may require sudo): `docker-compose up -d`
3. Copy `dev.env` to `.env` and customize as needed
4. Run command `mix deps.get`
5. Run command `make reset-db`
6. Compile web assets (this only needs to be done once and requires python2):
   `cd apps/nerves_hub_www/assets && yarn install`
7. Start web app: `make server` or `make iex-server` to start the server with the
   interactive shell

### Starting the application

1. Start the database (if not started): `docker-compose up -d`
2. Compile web assets (this only needs to be done once):
   `cd apps/nerves_hub_web/assets && yarn install`
3. Start web app: `make server` or `make iex-server` to start the server with the
   interactive shell
   * The whole app will need to be compiled the first time you run this, so
     please be patient

### Client-side SSL device authorization

NervesHub uses Client-side SSL to authorize and identify connected devices.
Devices are required to provide a valid certificate that was signed using the
trusted certificate authority NervesHub certificate. This certificate should be
generated and kept secret and private from Internet-connected servers.

For convenience, we use the pre-generated certificates for `dev` and `test`.
Production certificates can be generated by following the SSL certificate
instructions in `test/fixtures/README.md` and setting the following environment
variables to point to the generated key and certificate paths on the server.

```text
NERVESHUB_SSL_KEY
NERVESHUB_SSL_CERT
NERVESHUB_SSL_CACERT
```

### Tags

Tags are arbitrary strings, such as `"stable"` or `"beta"`. They can be added to
Devices and Firmware.

For a Device to be considered eligible for a given Deployment, it must have
*all* the tags in the Deployment's "tags" condition.

## Simulating a device

The [nerves_hub_client](https://github.com/nerves-hub/nerves_hub_client) is an
example OTP application that simulates a device.  It will connect to the
NervesHub server via a Phoenix Channel and can be used to exercise the server
for development and test.

See the
[nerves_hub_client/README.md](https://github.com/nerves-hub/nerves_hub_client/blob/master/README.md)
for more information.
