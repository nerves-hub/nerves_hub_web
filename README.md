# NervesHub

![GitHub Actions](https://github.com/nerves-hub/nerves_hub_web/actions/workflows/ci.yml/badge.svg?branch=main)

This is the source code for the NervesHub firmware update and device management
server.

**Important**

This is the 2.0 development branch of NervesHub. If you have been using
NervesHub prior to around April, 2023 and are not following 2.0 development, see
the [`maint-v1.0`
branch](https://github.com/nerves-hub/nerves_hub_web/tree/maint-v1.0). The
`maint-v1.0` branch is being used in production. 2.0 development is in progress,
and we don't have guides or good documentation yet. If you use the 2.0
development branch, we don't expect breaking changes, but please bear with us as
we complete the 2.0 release.

## Project overview and setup

### Development environment setup

For best compatibility with Erlang SSL versions, we use Erlang/OTP 23.0.4. If
you're coming to NervesHub without OTP 23 or earlier devices, don't worry about
this. OTP 23.0.4 is difficult to install on Apple M1/M2 hardware so developing
on Linux is highly recommended if you're keeping to the OTP 23.0.4 requirement.

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

In development you can login into a pre-generated account with the username
`nerveshub` and password `nerveshub`.

### Running Tests

1. Make sure you've completed your [database connection setup](#development-environment-setup)
2. Fetch and compile `test` dependencies: `MIX_ENV=test mix do deps.get, compile`
3. Initialize the test databases: `MIX_ENV=test mix ecto.migrate.reset`
4. Run tests: `make test`
