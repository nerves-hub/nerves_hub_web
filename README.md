# NervesHub

![GitHub Actions](https://github.com/nerves-hub/nerves_hub_web/actions/workflows/ci.yml/badge.svg?branch=main)

This is the source repository for the NervesHub firmware update and device management
server. Container images are available [on ghcr over here](https://ghcr.io/nerves-hub/nerves-hub). Issue reports, Pull Requests and feature requests are very welcome.

## Features

- Delivery of signed firmware to authenticated Nerves devices
- Robust and reliable, confirmed to work at a scale of hundreds of thousands of devices
- Hardware device certificate authentication using NervesKey
- Shared secret authentication for easy onboarding and simpler setups
- Self-hostable with minimal infrastructure, Dockerfile provided
- Remote IEx terminal for debugging and device recovery
- and more...

Now that NervesHub 2.x is released we will refer to it simply as NervesHub. The 1.x version is now Legacy NervesHub ([`maint-v1.0`
branch](https://github.com/nerves-hub/nerves_hub_web/tree/maint-v1.0)) and is under very limited maintenance and migration is strongly encouraged. The people that develop NervesHub no longer have 1.x environments running. See notes on migrating below.

## Migration from 1.x to 2.x

Migration should be quite straight-forward, there should not be any breaking changes. It is still the same application and NervesHubLink should stay largely compatible. You may find you no longer need a lot of the AWS services that was relied on by the 1.x version. We recommend decomissioning those if they aren't used for other things. Version 2.x requires an application server to run on, an S3-compatible object storage and a Postgres database. It also requires some control over how ingress is done for custom SSL handling. This should all be less than the requirements of Legacy NervesHub.

## Project overview and setup

### Development environment setup

For best compatibility with Erlang SSL versions, we use Erlang/OTP 27.0.1.

The `.tool-versions` files contains the Erlang, Elixir and NodeJS versions.
Install [asdf-vm](https://asdf-vm.com/) and run the following for quick setup:

```sh
cd nerves_hub_web

asdf plugin-add nodejs
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring # this requires gpg to be installed
asdf install
```

Modify the `.tool-versions` if you want to use a later version of Erlang.

You'll also need to install `fwup` and `xdelta3`. See the [fwup installation
instructions](https://github.com/fhunleth/fwup#installing) and the [xdelta3
instructions](https://github.com/jmacd/xdelta).


On Debian/Ubuntu, you will also need to install the following packages:

```sh
sudo apt install inotify-tools
```

Local development uses the host `nerves-hub.org` for connections and cert
validation. To properly map to your local running server, you'll need to add a
host record for it:

```sh
echo "127.0.0.1 nerves-hub.org" | sudo tee -a /etc/hosts
```

### First time application setup

1. Setup database connection

     NervesHub currently runs with Postgres 10.7. For development, you can use a local postgres or use the configured docker image:

     **Using local postgres**

     * Make sure your postgres is running
     * If you need to edit the `DATABASE_URL`, create a `.env.dev.local` and `.env.test.local` to adjust to your local postgres connection

2. Fetch dependencies: `mix do deps.get, compile`
3. Initialize the database: `mix ecto.reset`
4. Compile web assets (this only needs to be done once and requires python2 or a symlink for python3):
   `mix assets.install`

### Starting the application

* `mix phx.server` - start the server process
* `iex -S mix phx.server` - start the server with the interactive shell

> **_Note_**: The whole app may need to be compiled the first time you run this, so please be patient

Once the server is running, by default in development you can access it at http://localhost:4000

In development you can login into a pre-generated account with the email
`nerveshub@nerves-hub.org` and password `nerveshub`.

### Running Tests

1. Make sure you've completed your [database connection setup](#development-environment-setup)
2. Fetch and compile `test` dependencies: `MIX_ENV=test mix do deps.get, compile`
3. Initialize the test databases: `MIX_ENV=test mix ecto.migrate.reset`
4. Run tests: `make test`
