# AGENTS.md

Orientation for AI agents (and new engineers) working in `nerves_hub_web`.
It describes the codebase as it exists on `main`.

Keep this file current: when a change alters the layout, tooling, conventions,
or a gotcha below, update the relevant section in the same PR.

## What NervesHub is

NervesHub is the server for managing and deploying firmware to fleets of
[Nerves](https://nerves-project.org/) (embedded Elixir) devices. A device holds
a persistent socket connection to the server; through it the server ships
firmware updates and archives, drives remote console / local-shell sessions,
receives health/geo/log telemetry, and coordinates deployments. The web side is
a Phoenix LiveView dashboard plus a JSON API and a device-facing CLI.

## Runtime shape

A production cluster is **asymmetric**, and this shapes a lot of the code:

- **Device nodes** (many) terminate device socket connections. A given device's
  channels live on whichever device node it connected to.
- **Web nodes** (few) serve the dashboard, API, CLI, and run the deployment
  orchestrators.

Key runtime pieces:

- **Phoenix endpoints** — `NervesHubWeb.Endpoint` (dashboard/API), plus a
  device socket endpoint and a health-check endpoint.
- **Two data stores:**
  - **PostgreSQL** via `NervesHub.Repo` — core domain data (accounts, devices,
    firmware, deployments, …). Migrations in `priv/repo/`.
  - **ClickHouse** via `NervesHub.AnalyticsRepo` — high-volume analytics:
    device connection history, metrics, and the Insights pages. Migrations in
    `priv/analytics_repo/`. Reads/writes are **eventually consistent** (see
    [Testing](#testing)).
- **Background jobs** — Oban (`lib/nerves_hub/workers/`).
- **Deployment orchestration** — one singleton `Orchestrator` process per
  deployment group, owned by ProcessHub (`NervesHub.ManagedDeployments.Distributed`).
- **Presence/liveness** — `NervesHub.Tracker` + Phoenix Presence.
- **Cross-node messaging** — two transports. `Phoenix.PubSub` for dense
  fan-out, and the `group` library for per-entity topics whose consumers are
  sparse (per device, per console session, per product, per firmware). See
  [docs/cross_node_messaging.md](docs/cross_node_messaging.md) for which is
  which and how to choose for something new.

## Repository layout

```
lib/nerves_hub/       Contexts — business logic, no web concerns
lib/nerves_hub_web/   Web layer — endpoints, router, LiveViews, channels, API
test/                 Mirrors lib/; test/support/ has case templates + fixtures
config/               config.exs, runtime.exs, dev.exs, test.exs
priv/repo/            Postgres migrations
priv/analytics_repo/  ClickHouse migrations
assets/               JS/CSS (esbuild + tailwind)
rel/                  Release config
docs/                 Design docs
```

Every environment variable `config/runtime.exs` reads is documented in
[docs/runtime_configuration.md](docs/runtime_configuration.md); keep it in step
when adding or removing one.

### `lib/nerves_hub/` (contexts)

- `accounts.ex` / `accounts/` — users, orgs, org-users, tokens, scopes.
- `devices.ex` / `devices/` — device lifecycle, connections, health status,
  metrics, and network identities (a device's identity on networks NervesHub
  doesn't run, such as iroh or NetBird).
- `managed_deployments.ex` / `managed_deployments/` — deployment groups and the
  `Distributed.Orchestrator` (one per deployment).
- `firmwares.ex` / `firmwares/` and `archives.ex` / `archives/` — firmware and
  archive artifacts, uploads, and firmware **delta** building.
- `products.ex` / `products/` — products and product settings, including
  health profiles (the per-product thresholds behind device health status,
  evaluated in `devices/health_evaluation.ex`).
- `extensions.ex` / `extensions/` — the device **extension framework**
  (`health`, `geo`, `local_shell`, `logging`, `network_identity`,
  `error_reports`); extensions attach per-device and exchange messages over the
  extensions channel.
- `error_reports.ex` / `error_reports/` — exceptions devices report, grouped
  into issues. Split across both stores: the group in Postgres, the
  occurrences in ClickHouse. See [docs/error_reports.md](docs/error_reports.md).
- `scripts.ex` / `scripts/` — support scripts run against a device console.
- `workers/` — Oban workers (e.g. firmware delta building, firmware deletion).
- Cross-cutting: `audit_logs.ex`, `product_notifications.ex`, `tracker.ex`,
  `rate_limit.ex`, `cli_session_cache.ex`, `device_link.ex`, `repo.ex`,
  `analytics_repo.ex`, `application.ex`.

### `lib/nerves_hub_web/` (web)

- `channels/` — the device socket and its channels:
  - `DeviceSocket` (device-side socket; `id/1` is `device_socket:<id>`),
    `DeviceChannel`, `ConsoleChannel`, `ExtensionsChannel`.
  - User-facing counterparts: `UserConsoleChannel`, `UserLocalShellChannel`.
- `live/` — LiveViews (the dashboard). `live/devices/show.ex` is the device
  page; its tabs live in `components/device_page/*` as tab components that hook
  into the LiveView.
- `components/` — shared function/live components.
- `controllers/` — JSON API (`controllers/api/`) and others.
- `plugs/`, `router.ex`, `endpoint.ex`, `device_endpoint.ex`,
  `health_check_endpoint.ex`, `auth*.ex`.

## Tooling & running locally

- **Toolchain via [mise](https://mise.jdx.dev/)** (`.tool-versions`): Elixir
  1.20 / OTP 29, Erlang 29, Node 24. If mise isn't shell-activated, run mix
  through it: `mise x -- mix <task>`.
- **Services:** `docker compose up -d` starts PostgreSQL and ClickHouse.
- **First-time setup:** `mix setup` (fetches deps, runs `ecto.setup`, builds
  assets).
- **Run:** `mix phx.server` (or `iex -S mix phx.server`); dashboard at
  http://localhost:4000.
- **Env:** `DATABASE_URL` (Postgres), `CLICKHOUSE_URL` (ClickHouse) — defaults
  point at the docker-compose services.

## Conventions

- **Formatting:** `mix format`. The formatter runs the **Quokka** plugin
  (a Styler-style rewriter — it reorders aliases, rewrites pipes, normalizes
  module structure) plus the LiveView HTML formatter. Let it reshape your code;
  don't fight its output.
- **Static checks — run `mix check` locally before every PR; CI runs the
  equivalent steps individually:**
  - `mix compile --warnings-as-errors`
  - `mix format --check-formatted`
  - `mix deps.unlock --check-unused`
  - `mix dialyzer`
  - `mix credo --min-priority low`
  - `mix spellweaver.check` — spell check (cspell). New proper nouns / technical
    terms go in `.cspell.json`.
- **Boundaries:** contexts (`lib/nerves_hub/`) hold business logic; web modules
  stay thin and call into them. Match the surrounding module's conventions,
  error handling, and naming rather than importing your own.
- Never weaken a test, disable a lint, or add a suppression to get green — if
  you're blocked, say so.

### Cross-application contracts

A NervesHub cluster can be joined by other applications, which call context
functions over `:erpc` rather than reimplementing them. Distributed Erlang gives
no compile-time link, so **a context function can have no caller in this
repository and still be in use.** Renaming or removing one does not fail here;
it fails at runtime, in a deployment this repository cannot see.

Such a function says so in its `@doc`, in these words:

> Called over `:erpc` by other applications in the cluster

**Do not remove a function carrying that line because a search finds no local
caller.** That is what it is telling you. `grep -rn "Called over \`:erpc\`" lib/`
lists them.

When writing one:

- **Say it in the `@doc`**, using the line above so it can be found, along with
  what the caller uses it for and that having no local caller is expected.
- **Return plain maps, not schema structs.** A struct on a node that does not
  define its module is a map with a `__struct__` key pointing at nothing, which
  callers then work around.
- **Treat the return shape as published.** Adding a key is safe. Renaming or
  removing one breaks a caller you cannot see, so it needs a coordinated
  release.
- **Pin the shape in a test**, so a change that would break a remote caller
  fails here instead.

Keeping the marker in the `@doc` rather than in a list here is deliberate: the
fact belongs next to the code it constrains, and a list would go stale the
moment a consumer changed.

## Testing

- **Setup once:** `MIX_ENV=test mix test.setup`. **Run:** `mix test`.
- Postgres tests use the Ecto SQL **Sandbox**. Prefer running the full suite for
  a package you touch over a scoped module run — scoped passes hide breakage
  outside their scope.
- **Case templates** (`test/support/`):
  - `NervesHub.DataCase` — context / DB tests.
  - `NervesHubWeb.ConnCase` — controller tests. `NervesHubWeb.ConnCase.Browser` —
    UI / LiveView tests with PhoenixTest (see below).
  - `NervesHubWeb.ChannelCase` — channel tests.
  - `NervesHub.Fixtures` for fixtures; `SocketClient` simulates a real device
    connection.
- **UI / LiveView tests use [`PhoenixTest`](https://hexdocs.pm/phoenix_test).**
  Browser-style tests (`use NervesHubWeb.ConnCase.Browser`) drive the app through
  one high-level, page-oriented API that behaves the same on dead and live views,
  so you rarely touch `Phoenix.LiveViewTest` element/render plumbing directly.
  Start with `visit("/path")`, then:
  - **Assert:** `assert_has("selector", text: "…")`, `refute_has/…`,
    `assert_path("/…")`.
  - **Interact:** `click_button` / `click_link`, `fill_in` / `select` / `check` /
    `uncheck`, `submit`, and `within("selector", fn -> … end)` to scope actions.

  Each call returns the session, so tests read as a `|>` pipeline. For the rare
  thing PhoenixTest doesn't cover, `unwrap(fn view -> … end)` drops down to
  `Phoenix.LiveViewTest` (both are imported by `ConnCase.Browser`) — reach for it
  only for the gaps.
- **Known-flaky / environment-dependent (not code smells):**
  - **ClickHouse is eventually consistent.** Connection-history and Insights
    tests assert with `assert_eventually`; under a loaded runner they can fail
    and pass on re-run / in isolation. Verify with a re-run before assuming a
    regression.
  - **Firmware delta tests need `fwup` + `mtools` + `xdelta3` + `detools` installed.** (`detools` is pinned in `mise.toml`, so `mise install` fetches it; otherwise `pip install detools`. ESP-IDF deltas use it rather than xdelta3, because that is the format `esp_delta_ota` reads on the device.)
    Without them, a couple of `NervesHub.Firmwares.UpdateToolTest` cases fail
    locally — an environment failure, not a code one.

## CI

`.github/workflows/ci.yml`, by job:

- **Compile & Test** — the static gate (compile `--warnings-as-errors`, format,
  `deps.unlock --check-unused`, spellweaver, `credo --min-priority low`,
  dialyzer) plus the full suite, with Postgres + ClickHouse service containers.
- **Build & Publish Docker image** — builds and pushes the container image
  (on push, not PRs).
- **Submit Mix Dependencies** — submits the dependency graph; non-PR events only,
  because submission needs `contents: write`, which pull requests from forks
  don't get.
- **Dependency Review** — read-only review of a PR's dependency changes;
  `pull_request` only, so it works for outside contributors.

## Working here as an agent

- Read the actual code and trace call paths before changing anything; confirm
  helpers/types exist rather than assuming.
- One concern per change; leave unrelated problems as noted follow-ups.
- Document as you go — doc comments on anything public, and update touched docs
  (including this file).
- Flag security-relevant surface area (new inputs/endpoints/authz checks,
  anything touching secrets or crypto) when handing off.
