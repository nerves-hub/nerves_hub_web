# Cross-node Messaging

NervesHub moves messages between nodes two ways: `Phoenix.PubSub` and the
[`group`](https://hex.pm/packages/group) library. This document covers which
one carries what, how to choose for something new, and what to know when a
message does not arrive.

## Why there are two

A NervesHub cluster is asymmetric. A large fleet runs **many device nodes**,
each terminating a slice of the device socket connections, and **few web
nodes** serving the dashboard, API and CLI. Most internal messaging is between
a single device and whatever UI happens to be watching it — a device sends a
heartbeat, a health report or a stream of console bytes, and zero or one web
node has a LiveView or user channel open for it.

`Phoenix.PubSub` (the `pg` adapter) broadcasts every message to the pub/sub
server on **every** node, which then filters by local subscription. Subscribing
is free and node-local; publishing costs one message per node. For a per-device
topic with no watcher — the common case — every device event is shipped to all
N device nodes and discarded.

`Group.dispatch/3` inverts that. It delivers only to nodes holding a process
**joined** for a key, so a quiet device generates no cross-node traffic at all.
The cost moves to membership: a join or leave replicates to every node in the
cluster, and every node holds a row for every member.

## Choosing between them

> A topic earns `:group` when its **membership** is sparse and its **traffic**
> is not. Membership that tracks device connections never qualifies.

Sparse membership means the consumers exist only while somebody is looking —
an open LiveView, a live console session, an attached shell. Membership that
follows device connections is the opposite: it churns with the fleet, on every
connect and disconnect, whether or not anyone is watching.

Both halves of the rule matter. A rarely-published topic gains nothing from
targeted dispatch, so it is not worth paying membership replication for.

### What lives where

| Topic | Transport | Why |
| --- | --- | --- |
| `internal:device:<id>` — heartbeat, connection change, firmware validated, update progress, geo, logs | `:group` | Consumers are LiveViews and the events stream channel; usually none. Publishing is constant. |
| Console and local shell byte streams | `:group` | Members exist only during a live session; the streams are chatty. |
| `device:<id>:extensions`, **device → web** (`health_check_report`) | `:group` | Members are LiveViews watching the device page. |
| `device:<id>:extensions`, **web → device** (`health:check`, per-device `attach`/`detach`) | `Phoenix.PubSub` | The consumer is the device's own `ExtensionsChannel`, alive for the whole connection. `:group` would replicate a join per connect and a leave per disconnect across the fleet, to target a handful of operator-triggered messages. |
| `product:<id>`, `firmware:<id>`, `product_notifications:<id>` | `:group` | Consumers are open LiveViews. |
| `orchestrator:deployment:<id>` | `:group` | A single consumer — the one orchestrator for that deployment group — fed by every device node. |
| Rate-limit throttle sync, CLI-session cache | `:group`, `"web"` cluster | Web-only state that should not exist on device nodes at all. |
| `product:<id>:extensions` | `Phoenix.PubSub` | One operator toggle must reach *every* online device in the product. Genuine dense fan-out. |
| `deployment:<id>` | `Phoenix.PubSub` | Multi-subscriber, not a sparse per-entity topic. |

## Clusters

`:group` scopes replication with named clusters.

| State | Cluster | Participating nodes |
| --- | --- | --- |
| Device ↔ UI topics (device, console, extension reports, product/firmware UI, orchestrator) | default (`nil`) | All |
| Rate-limit throttle sync, CLI-session cache | `"web"` | Web/all nodes only |

The **default** cluster needs no explicit `connect` — nodes join through
automatic peer discovery on `:net_kernel` nodeup — so device-side senders and
web-side consumers find each other with no wiring.

The **`"web"`** cluster is opt-in. `NervesHub.GroupClusterConnection` calls
`Group.connect(NervesHub.Group, "web")` on startup for non-device nodes, and
`NervesHub.CLISessionCache` / `NervesHubWeb.RateLimitPubSub` are gated off
device nodes. All four sit under `NervesHub.GroupSupervisor` with a
`:rest_for_one` strategy: `Group` owns their cluster and group membership in
ETS, so if it restarts they have to re-run `init/1` against the fresh tree.

Note that `Group.join/4` and `Group.leave/3` raise if the node is not connected
to the named cluster, while `Group.dispatch/4` does not — it simply finds no
members. A missing `"web"` connection therefore fails loudly on join and
silently on dispatch.

## The wrapper modules

Group keys never appear at call sites. Each domain owns its keys behind a small
API:

| Module | Covers |
| --- | --- |
| `NervesHub.Devices.PubSub` | `internal:device:<id>` |
| `NervesHub.Consoles.PubSub` | Console and local-shell streams, and their liveness registries |
| `NervesHub.Extensions.PubSub` | Per-device extension traffic, both directions, and the product-wide topic |
| `NervesHub.Products.PubSub` | `product:<id>` |
| `NervesHub.Firmwares.PubSub` | Firmware delta build status |
| `NervesHub.DeploymentOrchestratorEvents` | Orchestrator events |
| `NervesHub.ProductNotifications` | Product notifications (in-module) |

Each module's `@moduledoc` carries the reasoning for its own keys — read those
before changing one.

Two conventions run through all of them:

- **Keys use `/` as the separator** (`internal:device/<id>`, `console/<id>`),
  because `/` is Group's hierarchy separator and keeps prefix queries
  available.
- **The `%Phoenix.Socket.Broadcast{}` `topic` string is preserved** as the
  original `Phoenix.PubSub` topic (`internal:device:<id>`, with a colon), so
  receivers that pattern-match on it keep working. Key and topic are different
  strings on purpose.

## Self-exclusion

`Phoenix.PubSub`'s `broadcast_from(self(), ...)` excludes the publishing
process. `Group.dispatch/4` has no equivalent, so flows that relied on it use
one of three approaches:

- **Pid exclusion** — `Products.PubSub.broadcast_from/3` iterates
  `Group.members/3` and sends to every pid except `self()`. The publisher is
  genuinely also a subscriber here: firmware create and delete run inside the
  Firmware LiveView, which is subscribed to the product and already refreshes
  from the mutation's own result.
- **Origin-node stamping** — `RateLimitPubSub` and `CLISessionCache` put
  `node()` in the message and drop it on receipt when it came from themselves,
  because the local write already happened inline.
- **Direction split** — `Extensions.PubSub` splits the per-device extensions
  topic by direction, so the device-side channel is never a member of the group
  it publishes reports to.

## When a message does not arrive

`:group` membership replicates asynchronously over Erlang distribution. Most
surprises trace back to that.

**Liveness is presence, not a probe.** `console_active?/1` and
`local_shell_active?/1` read `Group.members/3` on the local node's replica. A
device that just dropped can still read as available until its leave or DOWN
propagates, and longer under a partition. The console and shell tabs pair the
initial read with `Group.monitor/3` — monitor first, then read, so a change in
the gap arrives as an event rather than being lost — which corrects the
indicator without a page reload but does not remove the lag itself.

`Group.monitor/2` is backed by a duplicate-key registry, so it never reports
"already monitored" and repeated calls accumulate rows. The `Consoles.PubSub`
monitor helpers unregister before registering; do the same for any new one.

**Cold start.** A freshly started web node does not exchange rate-limit
increments or CLI-session writes with peers until `"web"` membership
propagates. `CLISessionCache` retries its warm-up for about 1.25 s to cover
this. The rate-limit increment always applies inline on the local node, so
cross-node throttling is briefly per-node rather than cluster-wide — a
defence-in-depth degradation, not a bypass.

**Rolling deploys.** The two transports do not talk to each other. While a
rollout has nodes on both sides of a change to which transport carries a topic,
mixed-version pairs will not exchange that topic's messages: console and shell
I/O, live device updates in the UI, health reports, rate-limit sync and
CLI-session writes all degrade for the duration and recover once the rollout
completes. Worth knowing before changing a topic's transport, and worth
mentioning in release notes when you do.

**Orchestrator failover.** Device nodes dispatch orchestrator events to the
node holding that deployment group's orchestrator. When ProcessHub moves or
restarts it, there is a window where events land nowhere. The orchestrator's
two-minute backup timer bounds this to a delayed update rather than a lost one.

## The dependency

`:group` is pre-1.0 and now carries console I/O, health reporting, the
rate-limit throttle and the CLI-session auth cache. It is pure Elixir with no
transitive dependencies and the `~> 0.2.0` requirement is tight, but its
releases should be tracked and upgrades reviewed rather than taken
automatically.
