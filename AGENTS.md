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
  device socket endpoint and a health-check endpoint. With `MAINTENANCE_MODE` set,
  a node starts `NervesHubWeb.MaintenanceEndpoint` and nothing else: no database,
  no cluster, no other endpoints (see
  [docs/runtime_configuration.md](docs/runtime_configuration.md)).
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
- **Node discovery** — libcluster topologies from `NervesHub.Clustering`:
  Postgres `LISTEN/NOTIFY` by default, or DNS (`CLUSTER_STRATEGY`). See
  [Clustering](docs/runtime_configuration.md#clustering).
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

- `accounts.ex` / `accounts/` — users, orgs, org-users, tokens, scopes, and
  roles, and the orgs each user stars on the home page (`Accounts.Starring`).
  `accounts/permissions.ex` is the catalog of every permission a member
  can hold and which built-in role (`admin`, `manage`, `view`) first gets it.
  An org can also define its own roles (`OrgRole`, managed through
  `accounts/org_roles.ex`), each a set of permissions from that catalog; a
  member holds a built-in role or a custom one, never both. A new
  `authorized?/2` check needs its permission added to the catalog first — an
  unknown permission raises rather than quietly denying. Controllers check the
  same permissions with `plug(:require_permission, :"firmware:upload" when
  action in [:create])`, and read-only actions with `plug(:require_membership)`
  (`helpers/permission_plugs.ex`). Every action and LiveView callback has to
  declare its check or it won't compile; see **Authorization** under
  [Conventions](#conventions).
- Two-factor authentication (`accounts/two_factor.ex`) is optional per user:
  an authenticator app (TOTP, through NimbleTOTP) plus ten single-use
  recovery codes. Its secret is encrypted with `Types.Encrypted`, so it is
  only offered when `SECRETS_ENCRYPTION_KEY` is set. Signing in goes through
  `NervesHubWeb.Auth.sign_in/4`, which stops at `/login/two-factor` for a
  user who has it on; a new way to sign in must use it too, or it skips the
  second step. An organization can require it of every member
  (`orgs.require_two_factor`): the browser and API pipelines, LiveView
  mounts, console, shell and device event stream channels, and Slack actions
  all turn away a member without it. A route that finds its org some other
  way than an `:org_name` in the path has to check for itself, as
  `API.Plugs.Device` does for `/api/devices/:identifier`. Turning the
  requirement on, or a member turning two-factor off, is announced on
  `Accounts.PubSub`, so what that member has open closes. Anything that
  checks a code limits the tries first (`Plugs.Attack`).
- An account signs in with a password, Google, or both
  (`Accounts.sign_in_methods/1`), and must keep one. Changing how it signs
  in (adding or removing a way, turning on two-factor) needs a **recent
  sign-in**, not a password: `NervesHubWeb.Auth.recently_authenticated?/1`
  reads `:authenticated_at` from the session (10 minutes). `/account/confirm`
  renews it with whichever way the account has, plus a two-factor code when
  two-factor is on, so an account without a password is never asked for one.
  A signed in user only reaches `/auth/google` with a `:google_intent` the
  account page set.
- A custom role can be limited to devices with certain tags. Its members see
  only those devices, so **every device query a user can reach must go through
  `NervesHub.Devices.Visibility.where_visible/2`**, which checks the member's
  role in SQL. Pages and endpoints built from all of a product's devices
  (Insights, deployment groups, firmware, ...) are closed to them instead:
  `on_mount(NervesHubWeb.Mounts.RequireEveryDevice)` for LiveViews,
  `plug(:require_every_device)` for controllers.
- `devices.ex` / `devices/` — device lifecycle, connections, health status
  (judged off the report path: reports queue an evaluation per device on a
  per-node `HealthEvaluation.Queue` with a fixed number of workers, so a slow
  ClickHouse never holds up a device's message), metrics, firmware update
  history (`update_history.ex` — how each update
  attempt ended, and for a success how long it took from being sent, split
  across both stores: the device's consecutive failure count in Postgres, the
  history itself in ClickHouse), and network identities
  (a device's identity on networks NervesHub doesn't run, such as iroh or
  NetBird). Each connection records the client library and version the device
  connected with (`lib` / `lib_version`), read from the `User-Agent` of its
  websocket upgrade by `client_library.ex`: listed clients under a fixed name,
  any other only if it opts in with a `custom#` prefix. Those rules are a wire
  contract with device clients; see
  [docs/device_client_identification.md](docs/device_client_identification.md).
  A device keeps one connection row (`latest_device_connections`), which
  started empty in April 2026, so a provisioned device with no row last
  connected before then (`Connections.last_seen_unrecorded?/2`). It is not
  "never connected" (that is a device still `registered`): `last_seen <`
  filters match it, Insights counts it as not seen in 14 days, and pages show
  its last seen as unknown.
  Each connection also records why it ended (`disconnect_reason.ex`, an enum
  stored as a string), and a device that says it is going to sleep is shown
  as asleep until it is due back rather than offline; see
  [docs/device_sleep.md](docs/device_sleep.md).
- `managed_deployments.ex` / `managed_deployments/` — deployment groups and the
  `Distributed.Orchestrator` (one per deployment). A release with a workflow
  is walked a step at a time (`Workflows`, `WorkflowCoordinator`); each step
  transition is announced to webhooks and Slack (`WorkflowEvents`).
  `Rollout` is how far a release has got, for the web UI: each group's and
  step's device counts from Postgres alone, the group's status (paused,
  stopped, awaiting approval, ...), and the devices it won't reach without
  help (penalty box, failed, updates off).
  `ReleaseStats` is how each release went, for a group's Stats tab, counted
  over the release's window (from when it was made until the next one): what
  its updates downloaded from `update_stats` in Postgres, and how attempts
  ended and how long they took from `device_update_history` in ClickHouse.
  The history began after some releases went out, so `kept?/2` says whether a
  release's numbers are whole, and the page shows a dash where they aren't.
- `firmwares.ex` / `firmwares/` and `archives.ex` / `archives/` — firmware and
  archive artifacts, uploads, and firmware **delta** building.
- `products.ex` / `products/` — products and product settings, including
  health profiles (the per-product thresholds behind device health status,
  evaluated in `devices/health_evaluation.ex`) and the device-managed updates
  grant new devices start with (applied in `Device.create_changeset/2`). Changes
  to a setting on every device in a product, from product settings, live in
  `devices/bulk_actions.ex`.
- `extensions.ex` / `extensions/` — the device **extension framework**
  (`health`, `metrics`, `alarms`, `geo`, `local_shell`, `logging`,
  `network_identity`, `error_reports`); extensions attach per-device and
  exchange messages over the extensions channel.
- `error_reports.ex` / `error_reports/` — exceptions devices report, grouped
  into issues. Split across both stores: the group in Postgres, the
  occurrences in ClickHouse. See [docs/error_reports.md](docs/error_reports.md).
  A product's Errors list (`live/product/errors.ex`) is read from PostgreSQL
  and filters on the issue row (reason, top frame, last-seen firmware); its
  sparklines and device counts load afterwards from ClickHouse in one task, and
  show a dash if it doesn't answer. An issue's page (`live/product/error_group.ex`)
  draws its chart on the server. What both pages share (badges, firmware labels,
  the sparkline and chart) is in `NervesHubWeb.Components.ErrorReports`.
- `webhooks.ex` / `webhooks/` — webhooks: device events POSTed to endpoints
  an organization configures, for every product or a chosen few (org
  Integrations page, or `API.WebhookController`). Events arrive through
  `Integrations.dispatch/3`. Deliveries are Oban jobs
  (`Workers.DeliverWebhook`), signed per Standard Webhooks, and only reach
  public addresses unless the instance allows otherwise. Event types and
  payloads are a published contract; see [docs/webhooks.md](docs/webhooks.md).
- `integrations.ex` / `integrations/` — where device events leave NervesHub.
  Code where an event happens calls `Integrations.dispatch/3` with the
  product, which costs one ETS read (`Integrations.Cache`) for a product
  nothing hears, and otherwise hands the event to the webhooks, Slack
  channels, and Teams and Discord channels that want it. `ProductScope` is the "every
  product, or these products" they share, and `ChannelEvents` the events a
  chat channel can be sent.
- `integrations/slack.ex` / `integrations/slack/` — the Slack integration: workspaces an organization
  connects by installing the instance's Slack app (`NervesHubWeb.Integrations.Slack.OAuthController`
  runs the OAuth flow), and the events Slack sends to `/integrations/slack/`,
  which must be signed (`Integrations.Slack.VerifyRequest`). One bot token per
  workspace, encrypted at rest with `Types.Encrypted`. `Slack.Subscriptions`
  posts device events to channels, held 15 seconds and rolled up into one
  message per kind (`Workers.PostSlackEvents`, `Slack.Messages`). Buttons on
  those messages are carried out by `NervesHubWeb.Integrations.Slack.Actions` as the
  NervesHub user the Slack user linked (`Slack.Users`), with that user's
  permissions checked at click time; `NervesHubWeb.Integrations.Slack.Commands` answers
  `/nerveshub` with the same checks (`Integrations.Slack.Actions.authorize/5`), and
  `NervesHubWeb.Integrations.Slack.WorkflowSteps` approves, retries or skips a deployment
  workflow step (`Integrations.Slack.Actions.authorize_in/6`), and
  `Slack.WorkflowMessages` edits the messages with those buttons once the
  step is dealt with, by any route. An instance Slack cannot reach sets
  `SLACK_APP_TOKEN` and gets the same events, clicks and commands over
  Socket Mode (`NervesHubWeb.Integrations.Slack.Socket`, two connections
  per web node) instead of at `/integrations/slack/`. `NervesHubWeb.Integrations.Slack.Unfurls`
  previews device and deployment group links posted in Slack, checked
  against whoever posted them. Hidden unless the instance has a Slack app;
  see [docs/slack.md](docs/slack.md).
- `integrations/chat_webhooks.ex` / `integrations/chat_webhooks/` — chat
  channels posted to through the incoming webhook their service gave: a
  Microsoft Teams Workflows webhook or a Discord channel webhook
  (`ChatWebhook`, one table, `provider` saying which). The webhook URL is the
  only credential, so it is encrypted and never shown again. Events are held
  and rolled up as Slack's are (`Workers.PostChatWebhookEvents`). Each
  service is a `ChatWebhooks.Provider`: `integrations/teams.ex` (URL checks,
  Adaptive Cards in `Teams.Cards`) and `integrations/discord.ex` (URL checks,
  embeds in `Discord.Embeds`). See [docs/teams.md](docs/teams.md) and
  [docs/discord.md](docs/discord.md).
- `insights.ex` / `insights/` - what a product's fleet is made of, for its
  Insights page: devices counted by connection, health and firmware version
  from PostgreSQL alone, and the version whose devices stand out as less
  healthy than the fleet. Stands out counts only devices online or seen in
  the last 7 days (`Insights.active_query/0`): a device that's gone can't
  report its health and stays on the firmware it left with, so counting it
  flags old versions for their dead devices. Its groupings match the devices
  list's filters, so each count links to the devices it counts. `insights/trends.ex` is how the
  fleet moved over a period (adoption, update outcomes, online, healthy),
  from ClickHouse. History keeps only changes, so the shares are walked back
  from today's live counts and are shares of today's fleet. A version's
  release is the first deployment group given it, or its upload if none was.
- `scripts.ex` / `scripts/` — support scripts run against a device console.
- `workers/` — Oban workers (e.g. firmware delta building, firmware deletion).
- `audit_logs.ex` / `audit_logs/` - the audit log, written from the templates
  in `audit_logs/templates/`. An entry a device's Activity tab shows passes a
  `kind:` (`AuditLog.kinds/0`), and the tab draws its icon from that, never
  from the description. A new kind of entry needs a kind and an icon in
  `NervesHubWeb.Components.DevicePage.ActivityTab`.
- `product_notifications.ex` / `product_notifications/` - what a product's
  Notifications page lists: things that need a person, raised by a
  `create_*_notification!` function and coalesced by `event_key`, so one
  that happens again counts up instead of adding a row. Each has a `kind`
  (`Notification.kinds/0`, which its `event_key` starts with). The text
  shown is written from the kind and metadata by `ProductNotifications.Copy`
  when it's shown, so changing the copy there changes it for old
  notifications too: a short version for the page, which shows what it's
  about beside it, and a full one naming it, stored as `title` and `message`
  for Slack, Teams and Discord. A kind raised per device
  (`Notification.device_kinds/0`) is rolled up into one card per product
  that opens to its devices, and the page, its counts and Insights all count
  cards. The page groups cards by day, filters by level, and dismisses one,
  a card or all. `ProductNotifications.Subjects` links each to what it's
  about, from its kind and the metadata key that kind names, and says when
  that has gone. A new kind needs `title`, `message` and `@needs` entries in
  `Copy` (and `rolled_up` if it's raised per device), an entry in `Subjects`
  if it's about something, and the add-then-write rollout `Notification`
  describes. Seed test or dev notifications through the
  `create_*` functions, not by hand, so they read as the real ones do.
- CLI logins (`Accounts.generate_cli_session_token/2` and the functions after
  it) live in `cli_session_cache.ex`, copied to every web node. Every change
  to one runs on a single owner node, picked from the login's token, so a
  change made there has to go through `CLISessionCache.get_and_update/2` with
  a named `{module, function, args}`, never a function, which a node on
  another build can't run. See
  [docs/cross_node_messaging.md](docs/cross_node_messaging.md#one-owner-per-cli-login).
- Cross-cutting: `clustering.ex`, `tracker.ex`,
  `rate_limit.ex`, `cli_session_cache.ex`, `device_link.ex`, `repo.ex`,
  `analytics_repo.ex`, `application.ex`. `list_query.ex` holds what the
  contexts' list functions share: escaping a search for `ilike` and reading a
  page number or size from params.

### `lib/nerves_hub_web/` (web)

- `channels/` — the device socket and its channels:
  - `DeviceSocket` (device-side socket; `id/1` is `device_socket:<id>`),
    `DeviceChannel`, `ConsoleChannel`, `ExtensionsChannel`.
  - User-facing counterparts: `UserConsoleChannel`, `UserLocalShellChannel`.
- `live/` — LiveViews (the dashboard). `live/devices/show.ex` is the device
  page; its tabs live in `components/device_page/*` as tab components that hook
  into the LiveView. The Health tab's History card opens with a connection lane
  (`components/device_page/connection_lane.ex`) over the span its charts show,
  drawn from `Devices.ConnectionTimeline`: time offline with why it began and
  where the device came back, and reconnects too quick to count as offline.
  Hovering or tapping an offline span darkens the charts' matching Offline
  bands (the `ConnectionLane` hook). Below `sm` the device page scrolls as one, under tabs
  that stick to the top, and each tab has its own `max-sm:` layout (a table
  becomes a card per row by restyling its rows, not by rendering them twice).
  Two states on a phone are marked on `<html>`, which a patch never touches,
  and read by the `header-scrolled:` and `terminal-typing:` variants in
  `app.css`. A file sent to a device on the Console tab shows how it's going
  in a dialog over the terminal and a strip under it, rendered by the tab and
  driven by `assets/js/helpers/consoleUploadView.js`. The device's console reads
  nothing else while it saves a file, so the page has to learn when it's done:
  a console from 2.1.0 on is asked by `ConsoleChannel` to report each chunk it
  saves (`file-data/ack`, then `file-data/saved` or `file-data/error`), and an
  older one is typed a character and Delete, the file being saved once that
  echoes. Only `ConsoleChannel` asks, never the page, since a channel that
  doesn't know the answers would crash on them. An organization's pages (`live/org/`, plus
  `live/products/new.ex`) have no sidebar: they render inside `Layouts.org/1`,
  a centered column under the organization's name, counts and tabs, and mount
  `NervesHubWeb.Mounts.OrgCounts` for the counts. Product pages keep the
  sidebar layout. The sidebar can be collapsed at any width, so the firmware
  list sizes its columns and cards by the room it gets (an `@container` and
  `@max-3xl:`-style variants), not by the viewport, and never scrolls sideways:
  a sideways scroller would clip each row's menu.
- `components/` - shared function/live components. `components/fleet_composition.ex`
  draws `NervesHub.Insights` on a product's Insights page, and
  `components/fleet_trends.ex` its trends row as SVG drawn on the server.
  `components/fleet.ex`
  sums up how a set of products is doing (Needs attention, online meters,
  health chips), for the organizations home page and an organization's
  Products tab. `components/device_list.ex` holds a product's devices list's
  state tabs (All, Online, Needs attention, Updating, Offline) and row cells;
  each tab is a `state` filter in `DeviceFiltering`, counted together by
  `Devices.state_counts/3`. Needs attention is a list rather than the table,
  split by why (`reason`: unhealthy, failing, not seen in 14 days); its
  definition lives in `DeviceFiltering.reason_dynamic/1`, and the row text in
  `DeviceList.attention_reason/2` must agree with it. Clicking a row (anywhere but its checkbox or
  identifier, which links to the device) opens `components/device_peek.ex`,
  a side panel for that device that only opens on a device the page lists;
  the `DevicePeek` hook gives it ↑ ↓ ↵ esc. The Filters button opens
  `components/device_filters.ex`, a panel that applies as it changes and shows
  what's applied as removable tokens under the query field. A filter in
  `DeviceFiltering.multi_filters/0` takes several comma-separated choices,
  any of which a device can match; each choice is a
  `DeviceFiltering.value_dynamic/2`, and the panel counts them with
  `Devices.facet_counts/4` only while it is open. The Columns button opens
  `components/device_columns.ex`, built the same way, which saves the
  columns shown to the user's display preferences as it changes. Selecting
  devices brings up `components/bulk_bar.ex`, a bar floating over the list whose buttons each
  open one popover (`bulk_menu` in the LiveView) for an action on all of
  them; every bulk action handler closes it, since a `phx-submit` command
  only sends its first push. Add device opens `components/add_device.ex`, a
  dialog over the list at `/devices/new` (the list's own `:new` action, so
  its query stays put). It adds a device matched by identifier through the
  product's shared secret, one with a secret of its own (shown once, then
  it waits for the device to connect), or one with its certificate. The
  tags line names the deployment groups they match
  (`ManagedDeployments.deployment_groups_matching_tags/2`). A product with no devices shows
  `components/device_onboarding.ex` and looks for its first one every few
  seconds; filters that match nothing show `DeviceList.no_matches/1`, which
  counts what removing each would bring back. A different list (filters, tab,
  page or sort) on its way dims the old one (`list_loading?`); a refresh of
  the same list doesn't. Its pager sits under the list (`DeviceList.pager/1`),
  not in the layout's footer. Below `sm` the same table rows are restyled into
  cards, so a column switched off still renders its cell, hidden from `sm`
  up. A phone has no headers to sort by or checkboxes to aim at: a line
  above the cards has a sort menu (`sort-by`) and a Select button, after
  which tapping a card selects it (`selecting?`) until Done. The peek, the
  Filters panel and the bulk bar's popovers become sheets from the bottom.
  `components/product_sidebar.ex` is the sidebar's product
  half on a product's pages (`Layouts.sidebar/1`): the product switcher and
  the page links, each carrying what needs looking at on its page (unhealthy
  devices, a release awaiting approval, open errors), counted as the page
  mounts. On a phone the sidebar is a drawer, and the top bar reads menu
  button, then the page's breadcrumb (or the product and page names when it
  has none), then the avatar, which holds the user menu the drawer leaves out.
  The user menu's contents are one component, `Layouts.user_menu_items/1`,
  shared by the sidebar's footer, that avatar and the header of pages without
  a sidebar, so a new link goes there once. A button that opens a menu points
  its chevron the way the menu opens (up in the footer, down for the product
  switcher) and flips it while open, read from its `aria-expanded`.
  Every detail, new and edit page draws its breadcrumb with
  `components/breadcrumb.ex` (the list's name, a chevron, then the item), so
  a new page uses it rather than writing its own. Asking before an action
  (deleting firmware, turning an extension off for every device, approving a
  step) goes through `Dialog.confirm/1` in `components/dialog.ex`, the design
  system's dialog: 440px, or 480px when it holds a list, with Cancel and the
  action under a divider, and a sheet from the bottom on a phone. A form that
  adds or edits something opens in `Dialog.form_dialog/1` from the same file
  (560px, or 600px when `wide`, with an optional icon tile and subtitle), its
  fields in `Dialog.form_body/1` and its buttons in `Dialog.form_footer/1`, as
  the release and integration dialogs do, so a new one uses it rather than
  writing its own. A short form, such as creating an API key, can use
  `Dialog.confirm/1`.
  `components/product_list.ex` holds what the firmware and archive lists
  share: the footer pager, the sort arrow, and how a UUID, a size and an
  upload time are written.
  A product's deployment groups (`live/deployment_groups/index.ex`) are split
  into Needs you (a step waiting for approval or stopped on failures, with the
  button that moves it on) and Running on their own, shown as rows or cards
  by the user's `deployment_group_view` preference. A group's page
  (`live/deployment_groups/show.ex`) opens on its Overview
  (`components/deployment_group_page/overview.ex`): a callout for a held
  step, the rollout and its steps, the devices the release didn't reach, and
  the release and matching rules. What both share (status badges, step bars,
  the approve and skip dialogs, and `DeploymentGroups.act/3`, which acts
  through `Workflows.act_on_held_step/3` so a step somebody already dealt with
  is refused) is in `components/deployment_groups.ex`, along
  with the form fields the Releases and Settings tabs draw (`field_class/2`,
  `textarea_class/2`, `select_control/1`).
  The group page asks before pausing or resuming the group and before moving
  devices into or out of it (`components/deployment_group_page/dialogs.ex`).
  One `@confirm` assign drives every dialog on the page, approve and skip
  included, and each refresh keeps it only while it would still change
  something; pausing and resuming set the group's state rather than flip it.
  Both pages reload their counts every few seconds while open. The group
  page's other tabs are LiveComponents in `components/deployment_group_page/`:
  Releases (the release history, and the New and Edit release dialogs, opened
  from `?new=release`; deleting a delta asks first, since every group sending
  the release shares it, and Remove connecting code only empties the field
  until the dialog is saved), Stats (`?release=` picks a release or `all`; its
  ClickHouse numbers load in a task and only when the choice changes), Activity
  (the group's audit log by day, paged in the URL, drawn as the device page's
  Activity tab is, so a change to one belongs in both) and Settings (cards that
  each save only their own fields, the workflow upload, and deleting the
  group; turning delta updates on or off needs
  `deployment_group:toggle_delta_updates`, as it does in the API, and saving
  drops the field for a member without it). There's no Devices tab: the header's device count links to the
  devices list, filtered to the group.
  Anything done to a release (creating or editing one, approving, skipping or
  retrying its workflow step, retrying or deleting its deltas), on these pages,
  the firmware and archive pages, Slack or the API, needs
  `deployment_group:release:manage`, and so does creating a group, which starts
  with a release. `deployment_group:update` is the group's own settings.
|   Queueing a release's deltas runs a transaction of its own, so it happens after
|   the release commits: a failed nested `Repo.transact` rolls back the outer
  one too, even when its result is ignored. So a release that will queue deltas
  starts `:preparing` (`DeploymentRelease.hold_for_deltas/2`) until the
  recalculation after the queueing settles it, and the group's orchestrator
  settles any left behind on its two-minute tick
  (`ManagedDeployments.settle_delta_statuses/1`).
  A product's settings are three LiveViews, General (`live/product/settings.ex`),
  Device health (`live/product/health_profiles.ex`) and API keys
  (`live/product/api_keys.ex`), sharing their title and tabs from
  `components/product_settings.ex`. General is titled cards in two columns,
  like the device page's Settings tab, and draws its toggles with
  `components/switch.ex`. Anything there that changes every device, or can't
  be undone, asks first in a `Dialog.confirm/1` that one assign drives
  (`@confirm` on General, `@dialog` on API keys); each event that opens one
  checks the same permission as the event that acts. API keys uses it for its
  create form and deactivating a key too, and for the one-time key, which sets
  `dismissible` to false: no Cancel, and Escape and a click outside do
  nothing, so a stray click can't throw the key away. The dialog must not
  clip, because the API keys role picker is a popover that hangs past the
  footer. Device health edits one profile at a time as a draft, saved whole by
  `HealthProfiles.save_metrics/2`. While there are unsaved changes it shows
  what saving would do to the profile's devices: today's `device_health`
  counts, moved by the difference between ClickHouse previews of the saved
  and edited metrics (`HealthProfiles.preview_counts/5`), which judge every
  device the way `HealthEvaluation` does but leave out readings still in the
  analytics buffer.
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
- **Icons:** `lucide-<icon>[--<weight>]` classes come from
  `assets/vendor/lucideicons.js`, which only generates a class for each SVG in
  `deps/lucide/icons`. Lucide renames icons between releases, and a class whose
  icon is gone renders as nothing, so `NervesHubWeb.LucideIconsTest` fails on
  any class with no SVG behind it. A line icon draws its stroke at 1/16 of its
  size and never under 1px: plain `lucide-<icon>` is that weight, `--bold` is
  for a selected nav item or an icon under 16px, and `--thin` for 32px and up.
  `--fill` fills the glyph in, for a closed shape that shows something is on
  (a starred organization's star); an open glyph like a chevron fills oddly.
  Every icon is a Lucide glyph, either a `lucide-*` span or `<.icon name="…">`
  (`NervesHubWeb.Components.Icons`, which names the ones used across pages).
  The glyph is a mask filled with `currentColor`, so a `text-*` class colours
  it, never `stroke-*` or `fill-*`. Inline SVG is for logos and illustrations.
  A `<.button>` holding only an icon sets `square`, or it comes out shorter
  than the text buttons beside it. A file picker is `<.button type="label">`
  with `for` set to the upload's ref.
- **Fonts:** Inter (the sans) and JetBrains Mono (`--font-mono`) are vendored
  in `priv/static/fonts/`, each straight from its upstream release with its OFL
  license, and declared with `@font-face` in `assets/css/app.css`. `@theme`
  sets `--font-sans` to Inter, so `font-sans` (stepping back out of mono) is
  Inter rather than Tailwind's system-ui stack. The maintenance page declares
  Inter in its own inline CSS (`MaintenanceEndpoint` serves `fonts` for it).
  JetBrains Mono has no variable woff2, so only the weights mono text uses are
  there (400, 500, 600); a heavier or italic mono style needs its file added.
  xterm and chart.js draw on a canvas, so they name the font themselves in
  `assets/js` and wait for it with `whenFontsLoaded`.
  Self-hosted instances may have no internet access, so don't load fonts or
  other assets from a third-party CDN.
- **Type sizes and card corners:** sizes off Tailwind's scale are named in the
  `@theme` block of `assets/css/app.css`, so use the name, not a bracketed
  size: `text-ui` (13px interface text, with `/4` or `/4.5` for its line
  height), `text-label` (the 11px uppercase label over a column or a figure),
  `text-2xs` (11px that isn't a label: a keyboard key, a count badge, a
  chart's legend; nothing smaller outside a chart), five headings
  (`text-home-title`, `text-page-title`, `text-section-title`,
  `text-card-title` for a card, list, panel or top bar title, and
  `text-group-title`), and three figures (`text-figure-xl`, `text-figure`,
  `text-figure-sm`). A count on a card is the sans at the token's weight; a
  value read as a reading is `font-mono text-figure font-normal`. Every card,
  panel and dashed placeholder is `rounded-card` (4px), along with its
  `rounded-t-card` header and `rounded-b-card` footer. Controls keep
  `rounded`, menus `rounded-md`, meters `rounded-full`, and checkboxes and
  legend swatches `rounded-xs`.
- **The instance's name:** NervesHub also runs under other names
  (NervesCloud), so text a person reads, on a page, in a flash or an error, or
  in a message sent to Slack, Teams or Discord, names the instance with
  `NervesHub.Branding.friendly_platform_name()` (`FRIENDLY_PLATFORM_NAME`), not
  "NervesHub". Call it as the text is built, never in a module attribute, which
  would fix the name at compile time. Docs, API spec descriptions, user agents
  and links to the NervesHub documentation keep the name.
- **Boundaries:** contexts (`lib/nerves_hub/`) hold business logic; web modules
  stay thin and call into them. Match the surrounding module's conventions,
  error handling, and naming rather than importing your own.
- **Authorization** is declared, so forgetting it fails the build. A browser
  can send a LiveView any event, shown on the page or not, so every clause of
  a LiveView's `mount/3`, `handle_params/3`, `handle_event/3` and
  `handle_progress/3`, a LiveComponent's `handle_event/3` and
  `handle_progress/3`, and a device tab's `hooked_event/3` and
  `handle_progress/3` carries a decorator (`NervesHubWeb.AuthorizationDeclared`):
  - `@decorate requires_permission(:"device:update")` for anything that needs
    a permission. It checks before the body runs, so don't also call
    `authorized!/2` at the top of the body.
  - `@decorate requires_membership()` for what any member may do on an
    organization's pages: reading, paging, filtering, opening a form.
  - `@decorate requires_no_permission()` outside any organization, or for a
    clause that only passes the event on.
  - `@decorate authorizes_in_body(:reason)` when the permission depends on
    what the body loads or on the params. The body must then call
    `authorized!/2` itself.

  Every controller action is covered the same way by a plug
  (`NervesHubWeb.ControllerAuthorizationDeclared`): `require_permission`,
  `require_membership`, or `plug(:require_no_permission, :reason)` for
  sign-in pages and requests that prove themselves (a Slack signature). A
  refusal raises `NervesHubWeb.UnauthorizedError` everywhere.
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
- **The OpenAPI spec is checked against real responses.**
  `test/nerves_hub_web/api_spec_test.exs` checks that every documented path is
  routed, every schema example fits its schema, and no two schemas share a
  title (the spec keys them by title, so one would replace the other). It also
  sends real requests through
  `NervesHubWeb.APISpecAssertions.assert_documented_response/2`, which fails
  on an undocumented status code, a field sent but not documented, or one
  documented but never sent. A change to an API response or status code
  updates the spec in the same PR, and a new endpoint adds a case there.
  Record timestamps (`inserted_at`, `updated_at`) are naive and go out with
  no offset, so their schemas use `SchemaHelpers.naive_timestamp/1`, not
  `format: :"date-time"`.
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

`.github/workflows/image-scan.yml` runs Trivy over the published image every day
and fails on a fixable critical or high finding. It doesn't block pull requests.

## Container image

The runtime image runs as uid 65532, not root. The app can only write to
`/app/tmp` and the system temp directory, so anything new that writes to disk has
to use one of those. It can't bind a port below 1024 unless the container runtime
allows it (see `DEVICE_PORT` in
[docs/runtime_configuration.md](docs/runtime_configuration.md)).

## Working here as an agent

- Read the actual code and trace call paths before changing anything; confirm
  helpers/types exist rather than assuming.
- One concern per change; leave unrelated problems as noted follow-ups.
- Document as you go — doc comments on anything public, and update touched docs
  (including this file).
- Flag security-relevant surface area (new inputs/endpoints/authz checks,
  anything touching secrets or crypto) when handing off.
