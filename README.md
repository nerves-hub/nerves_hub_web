# NervesHub

![GitHub Actions](https://github.com/nerves-hub/nerves_hub_web/actions/workflows/ci.yml/badge.svg?branch=main)

NervesHub is an open-source resilient firmware update and device management platform that scales with your fleet.

Pre-built Docker images are available via the [GitHub Container Registry](https://ghcr.io/nerves-hub/nerves-hub). 

Issue reports, Pull Requests and feature requests are very welcome.

## Features

- Delivery of signed firmware to authenticated Nerves devices
- Robust and reliable, confirmed to work at a scale of hundreds of thousands of devices
- Hardware device certificate authentication
- Shared secret authentication for easy onboarding and simpler setups
- Self-hostable with minimal infrastructure, Dockerfile provided
- Remote IEx terminal for debugging and device recovery
- A comprehensive API documented using OpenAPI
- and more...

---

## Sponsors

NervesHub development is sponsored by:

<a href="https://nervescloud.com"><img src="https://files.nervescloud.com/images/logo-nervescloud-light.svg" width="225" alt="NervesCloud"  style="padding-right: 40px;"></a> &nbsp;&nbsp;&nbsp;&nbsp; &nbsp;&nbsp;&nbsp;&nbsp; &nbsp;&nbsp;&nbsp;&nbsp; <a href="https://smartrent.com"><img src="https://s27.q4cdn.com/632832908/files/design/logo/2024/smartrent-logo_color.png" width="325" alt="SmartRent"></a>

---

## Project overview and setup

### Development environment setup

The `.tool-versions` files contains the Erlang, Elixir and NodeJS versions.

While [mise](https://mise.jdx.dev/) is recommended, you can also use [asdf-vm](https://asdf-vm.com/) if you prefer. 

Modify the `.tool-versions` if you want to use a later version of Erlang, Elixir, or NodeJS.

You'll also need to install `fwup` and `xdelta3`. See the [fwup installation
instructions](https://github.com/fhunleth/fwup#installing) and the [xdelta3
instructions](https://github.com/jmacd/xdelta).

If you are using a Debian/Ubuntu system, it's recommended to install the `inotify-tools` package:

```sh
sudo apt install inotify-tools
```

### First time application setup

1. Setup database connection

     Postgres 18 is recommended for development and running in production environments. You can use a local postgres or use the included Docker compose:

     ```sh
     docker compose up -d
     ```

2. Run `mix setup` to fetch dependencies, initialize the database, and compile web assets.

### Starting the application

* `mix phx.server` - start the server process
* `iex -S mix phx.server` - start the server with the interactive shell

Once the server is running, by default in development you can access it at http://localhost:4000

In development you can login into a pre-generated account with the email
`nerveshub@nerves-hub.org` and password `nerveshubweb`.

### Running Tests

1. Make sure you've completed your [database connection setup](#development-environment-setup)
2. Fetch and compile `test` dependencies: `MIX_ENV=test mix test.setup`
4. Run tests: `mix test`

### Using v1.x

The 1.x version is now Legacy NervesHub ([`maint-v1.0`
branch](https://github.com/nerves-hub/nerves_hub_web/tree/maint-v1.0)) and is under very limited maintenance. Migration to v2.x is strongly encouraged. 

#### Migration from 1.x to 2.x

Migration should be quite straight-forward, there should not be any breaking changes. It is still the same application and NervesHubLink should stay largely compatible. 

You may find you no longer need a lot of the AWS services that was relied on by the 1.x version. We recommend decommissioning those if they aren't used for other things. 

Version 2.x requires an application server to run on, an S3-compatible object storage and a Postgres database. It also requires some control over how ingress is done for custom SSL handling. This should all be less than the requirements of Legacy NervesHub.
