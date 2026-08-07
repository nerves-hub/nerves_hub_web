# 1. Use the `:group` library for targeted device → UI PubSub

Date: 2026-08-07

## Status

Accepted (pending merge of PR #2851).

## Context

A NervesHub cluster is asymmetric: a large fleet runs **many device nodes**
(each terminating a slice of the device socket connections) and **few web
nodes** (serving the dashboard, API, and CLI). Most of our internal messaging
is between a single device and whatever UI happens to be watching it — a device
sends a heartbeat/health report/console byte stream, and zero or one web node
has a LiveView or user channel open for it.

`Phoenix.PubSub` (PG2/`pg` adapter) broadcasts every message to the pub/sub
server on **every** node in the cluster, which then filters by local
subscription. For a per-device topic with no watcher — the common case — that
means every device event is shipped to all N device nodes and discarded. On a
fleet with tens of device nodes this is a large amount of cross-node traffic
delivered to nodes that have no subscriber.

The topics involved are almost all **sparse fan-out** (0–2 consumers, known to
live on web nodes):

- `internal:device:<id>` — device → UI events (heartbeat, connection change,
  firmware validated, update progress, geo, logs).
- console and local-shell byte streams (`device:console:<id>`,
  `user:console:<id>`, `user:local_shell:<id>`, …).
- `device:<id>:extensions` — per-device health/geo extension traffic.
- product/firmware UI topics (`product:<id>`, `firmware:<id>`,
  `product_notifications:<id>`).

A separate class of state is **web-node-only** and should never touch device
nodes at all: the PlugAttack IP throttle sync (which guards the
`check_cli_session` API action) and the CLI-session cache.

We wanted delivery scoped to the nodes that actually hold a
consumer, and web-only state kept off device nodes entirely.

## Decision

Adopt the [`:group`](https://hex.pm/packages/group) library (`~> 0.2.0`) — an
eventually-consistent distributed process-group / registry with **named
subclusters** and node-targeted `dispatch` — for these topics. `Group.dispatch`
delivers only to nodes that have a process **joined** for a key, so a quiet
device generates no cross-node traffic.

Concrete shape:

1. **Per-domain wrapper modules** own the group keys and hide `:group` behind a
   small API: `NervesHub.Devices.PubSub`, `NervesHub.Consoles.PubSub`,
   `NervesHub.Extensions.PubSub`, `NervesHub.Products.PubSub`, plus the
   in-module conversions in `Firmwares` and `ProductNotifications`. Every
   dispatch carries a `%Phoenix.Socket.Broadcast{}` struct whose `topic` string
   is **preserved** as the old `Phoenix.PubSub` topic, so existing
   `handle_info(%Broadcast{...})` / `hooked_info(...)` receiver clauses are
   unchanged — only the subscribe/broadcast call sites move.

2. **Cluster mapping:**

   | State | Cluster | Roles that participate |
   |---|---|---|
   | device ↔ UI topics (device, console, extensions, product/firmware UI) | **default** (`nil`) | all nodes |
   | rate-limit throttle sync, CLI-session cache | named **`"web"`** | web/all nodes only |

   The **default** cluster requires no explicit `connect` — nodes join it via
   automatic peer discovery (`:net_kernel` nodeup) — so device-side senders and
   web-side consumers find each other with no extra wiring. The **`"web"`**
   named cluster is opt-in: `NervesHub.GroupClusterConnection` calls
   `Group.connect(NervesHub.Group, "web")` on startup for non-device nodes, and
   `RateLimitPubSub` / `CLISessionCache` are gated off device nodes and started
   after the connection.

3. **Self-exclusion** — `Phoenix.PubSub`'s `broadcast_from(self(), ...)` excluded
   the publishing process; `Group.dispatch` has none. We preserve prior
   behaviour three different ways depending on the flow:

   - **Pid exclusion** (`Products.PubSub.broadcast_from/3`): the publisher is
     also a subscriber (firmware create/delete runs inside the Firmware
     LiveView), so we iterate `Group.members` and `send/2` to every pid except
     `self()`.
   - **Origin-node stamping** (`RateLimitPubSub`, `CLISessionCache`): the
     message carries `node()`; the receiving GenServer drops it when
     `origin == node()` because the local write already happened inline.
   - **Direction-split keys** (`Extensions.PubSub`): the device-side channel is
     both a member and the origin of the report flow, so the topic is split
     into `device:extensions/<id>` (web → device) and
     `device:extensions:reports/<id>` (device → web). No process is ever both a
     sender and a member of the same key, so nothing receives its own message.

4. **Kept on `Phoenix.PubSub` deliberately:**

   - `product:<id>:extensions` — a single operator toggle must reach *every*
     online device in the product. That is genuine dense fan-out with no
     targeted-dispatch win, and moving it to `:group` would trade a rare
     broadcast for continuous membership churn as devices connect/disconnect.
   - `deployment:<id>` — multi-subscriber, not a sparse per-entity topic.

## Consequences

**Positive**

- Device → UI, console, and extension traffic is delivered only to nodes with a
  live consumer; idle device nodes stop receiving-and-discarding other devices'
  events.
- Rate-limit and CLI-session-cache state — and its membership — no longer exist
  on device nodes.
- Liveness checks (`console_active?`, `local_shell_active?`, `shell_active?`)
  became `Group.members(key) != []`, dropping the previous up-to-500 ms
  blocking `{:active?}` broadcast-and-wait probe on tab load.

**Negative / tradeoffs**

- **Eventual consistency.** Group membership replicates asynchronously over
  Erlang distribution. Consequences:
  - *Liveness is now presence, not a probe.* A device that just dropped can
    still read as "console available" until its `leave`/DOWN event propagates
    (longer under a partition). A follow-up should move the availability
    indicator to `Group.monitor/3` push events (see below) rather than a
    point-in-time `members/2` read.
  - *Cold-start window.* A freshly started web node does not exchange
    rate-limit increments or CLI-session writes with peers until `"web"`
    membership propagates. `CLISessionCache` explicitly retries its warm-up for
    ~1.25 s to cover this. The rate-limit increment is always applied inline on
    the local node, so cross-node throttling is briefly per-node rather than
    cluster-wide — a defense-in-depth degradation, not an auth bypass.
- **New pre-1.0 dependency on critical paths.** `:group` now carries console
  I/O, health reporting, the rate-limit throttle, and the CLI-session auth
  cache. It is pure Elixir with zero transitive dependencies and the `~> 0.2.0`
  pin is tight (`>= 0.2.0` and `< 0.3.0`), but its releases should be tracked
  and upgrades reviewed.
- **Two mental models to hold.** Operators debugging "why didn't node X get
  this message" must know the default-vs-`"web"` cluster split and the
  device-vs-web role model. This ADR is the canonical reference for that.

## Follow-ups

- **Reactive availability via `Group.monitor/3`.** Replace the poll-style
  `Group.members(key) != []` liveness read in the console/shell UI with a
  monitor subscription so the indicator self-corrects on join/leave. Seed the
  initial state and then subscribe (monitor first, then read `members/2`, and
  dedupe) to avoid missing an event in the gap. This does not remove
  propagation lag, but it removes stale-until-next-render.
- Consider a small operational note in the deploy runbook pointing at this ADR.

## References

- PR #2851 — "Use the `:group` library for targeted device → UI PubSub".
- Wrapper module docs: `lib/nerves_hub/{devices,consoles,extensions,products}/pub_sub.ex`.
- `lib/nerves_hub/group_cluster_connection.ex`, `lib/nerves_hub/application.ex`.
