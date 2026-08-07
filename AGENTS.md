# AGENTS.md

Orientation for AI agents (and new engineers) working in `nerves_hub_web`.
It describes the codebase **as it exists on `main`**; large in-flight changes
are called out under [Active architectural work](#active-architectural-work).

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
- **Cross-node messaging** — `Phoenix.PubSub` on per-entity topics (a targeted
  `:group` migration is in flight — see
  [Active architectural work](#active-architectural-work)).

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

### `lib/nerves_hub/` (contexts)

- `accounts.ex` / `accounts/` — users, orgs, org-users, tokens, scopes.
- `devices.ex` / `devices/` — device lifecycle, connections, health status,
  metrics.
- `managed_deployments.ex` / `managed_deployments/` — deployment groups and the
  `Distributed.Orchestrator` (one per deployment).
- `firmwares.ex` / `firmwares/` and `archives.ex` / `archives/` — firmware and
  archive artifacts, uploads, and firmware **delta** building.
- `products.ex` / `products/` — products and product settings.
- `extensions.ex` / `extensions/` — the device **extension framework**
  (`health`, `geo`, `local_shell`, `logging`); extensions attach per-device and
  exchange messages over the extensions channel.
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
- **Static checks — run before every PR (CI runs the same via `mix check`):**
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

## Testing

- **Setup once:** `MIX_ENV=test mix test.setup`. **Run:** `mix test`.
- Postgres tests use the Ecto SQL **Sandbox**. Prefer running the full suite for
  a package you touch over a scoped module run — scoped passes hide breakage
  outside their scope.
- **Case templates** (`test/support/`):
  - `NervesHub.DataCase` — context / DB tests.
  - `NervesHubWeb.ConnCase` and `NervesHubWeb.ConnCase.Browser` — controllers and
    LiveView tests (LiveView via [`phoenix_test`](https://hexdocs.pm/phoenix_test):
    `visit` / `assert_has` / `refute_has`).
  - `NervesHubWeb.ChannelCase` — channel tests.
  - `NervesHub.Fixtures` for fixtures; `SocketClient` simulates a real device
    connection.
- **Known-flaky / environment-dependent (not code smells):**
  - **ClickHouse is eventually consistent.** Connection-history and Insights
    tests assert with `assert_eventually`; under a loaded runner they can fail
    and pass on re-run / in isolation. Verify with a re-run before assuming a
    regression.
  - **Firmware delta tests need `fwup` + `mtools` + `xdelta3` installed.**
    Without them, a couple of `NervesHub.Firmwares.UpdateToolTest` cases fail
    locally — an environment failure, not a code one.

## CI

`.github/workflows/ci.yml` runs, by function:

- **compile-and-test** — the `mix check` static gate plus the full test suite,
  with Postgres + ClickHouse service containers.
- **build-and-publish** — builds and pushes the Docker image (on push, not PRs).
- **report_mix_deps** — submits the dependency graph to GitHub and reviews PR
  dependency changes. Note: dependency-graph submission needs `contents: write`,
  which pull requests **from forks** don't get (GitHub forces a read-only token
  regardless of `permissions:`), so it currently fails for outside contributors;
  PR #2852 splits it so the submission runs only on push and PRs run a read-only
  review.

## Working here as an agent

- Read the actual code and trace call paths before changing anything; confirm
  helpers/types exist rather than assuming.
- One concern per change; leave unrelated problems as noted follow-ups.
- Document as you go — doc comments on anything public, and update touched docs
  (including this file).
- Flag security-relevant surface area (new inputs/endpoints/authz checks,
  anything touching secrets or crypto) when handing off.

## Active architectural work

Large changes in flight on open PRs that are **not on `main` yet** — expect to
see them on branches and in review:

- **PR #2851 (`use-group-for-smarter-pubsub`)** — migrates per-entity
  `Phoenix.PubSub` topics (device→UI events, console/shell byte streams,
  per-device extensions, and sparse product/firmware UI topics) onto the
  [`:group`](https://hex.pm/packages/group) library for **node-targeted
  dispatch**, so a message is delivered only to nodes that actually hold a
  consumer instead of fanning out to every device node. It also replaces the
  console/shell "is it live?" 500 ms broadcast-and-wait probe with a
  presence/`Group.monitor` model. Full rationale and the web/device cluster
  topology are in `docs/adr/0001-group-library-for-targeted-pubsub.md` on that
  branch.
- **PR #2791 (`mc-upload-writer`)** — a `Phoenix.LiveView.UploadWriter`
  (`BrieflyUploadWriter`) that streams firmware/archive uploads straight to a
  temp file the LiveView owns, dropping the current upload-then-copy
  double-write.

Until these merge, `main` uses `Phoenix.PubSub` throughout for cross-node
messaging and the copy-based upload path. When they land, fold their specifics
into the sections above and trim this note.
