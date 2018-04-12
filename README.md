# beamware

A domain independent back end solution for rolling out software updates to edge
devices connected to IP based networking infrastructure.

## Project Overview and Setup

### Language Versions

* Elixir 1.6+

### Initial App Setup

* Create directory for local data storage: `mkdir ~/db`
* Start the database (if not started): `docker-compose up -d`
* Copy `dev.env` to `.env` and customize as needed
* Run command `mix deps.get`
* Run command `make reset-db`
* Start web app: `make server` or `make iex-server` to start the server with the
  interactive shell

### Starting App

* Start the database (if not started): `docker-compose up -d`
* Start web app: `make server` or `make iex-server` to start the server with the
  interactive shell
  * The whole app will need to be compiled the first time you run this, so
    please be patient

### Tags

Tags are arbitrary strings, such as `"stable"` or `"beta"`. They can be added to
Devices and Firmware.

For a Device to be considered eligible for a given Deployment, it must have
*all* the tags in the Deployment's "tags" condition.

