# The Extensions Protocol

An extension is something NervesHub can ask a device for that is not firmware:
health metrics, a location, logs, a shell. Extensions are negotiated rather
than assumed, and this document is what that negotiation is. Until now the
only statement of it was `nerves_hub_link`'s implementation, which is why two
of the other clients diverged from it.

Two rules shape everything below. Extension traffic must never get in the way
of an update, so extensions are negotiated after the device topic is joined and
never before. And both sides have to agree, so an extension nobody asked for is
never sent: a device that starts reporting something an operator did not turn
on is worse than one that reports nothing.

## The handshake

Four frames, in this order.

```text
1.  server -> device   extensions:get        {"extensions": {"logging": ["0.1.0", "0.0.1"], ..}}
2.  device -> server   phx_join "extensions" {"logging": "0.1.0", "health": "0.0.1"}
3.  server -> device   phx_reply             ["logging", "health"]
4.  device -> server   logging:attached      {}
```

**1. The platform asks, and says what it has.** Sent once the device has joined
the `device` topic, and only to devices declaring `device_api_version >=
2.2.0`. The payload is every version of every extension this deployment
implements and has switched on, newest first per key. An extension turned off
for the deployment is absent entirely.

**2. The device answers by joining.** One version per extension, and only
extensions it wants to serve. This frame is the device's commitment: there is
no second choice in it, which is why frame 1 exists.

A client must not join the `extensions` topic before frame 1 arrives. Joining
early is accepted by the platform, but it means declaring versions without
knowing what the platform has, which is the thing the advertisement is for.

**3. The platform replies with the attach list.** The subset of what the device
offered that this *particular* device may use, which is narrower than what the
platform implements: an extension can be turned off per product or per device.
Keys only, no versions — the device already knows what it declared.

An extension left out here is not attached. A device should treat that as a
fact worth reporting locally, since from the outside it is indistinguishable
from a feature quietly not working.

**4. The device confirms each one.** Only after `<key>:attached` does the
platform start asking that extension for anything.

Everything after the handshake is scoped `<key>:<event>` in both directions.

## Choosing a version

For each extension it implements, a client walks **its own** versions, most
preferred first, and takes the first that also appears in the platform's list
for that key. Match by string equality; there is no version arithmetic to do
here, and requiring it would mean a version parser in Erlang on AtomVM and
another in Rust to answer a question the platform has already answered by
listing what it has.

- **No overlap for a key**, or **the key is absent** from the advertisement:
  omit it from the join. The platform cannot serve anything the device speaks.
- **No advertisement at all**: declare the **lowest** version of each extension
  the client implements. That is the version most likely to be understood by a
  platform old enough not to advertise.

A client must not wait indefinitely for frame 1. A platform that predates the
advertisement never sends it, and a client that waits forever loses every
extension against those platforms. **Join anyway five seconds after the device
topic's join reply**, using the fallback versions above.

## Adding a version of an extension

Platform side, in `NervesHub.Extensions`:

```elixir
@implementations [
  logging: [
    {"0.1.0", "~> 0.1.0", Logging.Batched},
    {"0.0.1", "~> 0.0.1", Logging}
  ],
  ...
]
```

One row per version, newest first, and the only place a version is written
down. `module/2` reads it to serve a device, `versions/1` and `advertisement/0`
read it to tell devices what is on offer.

The row is `{advertised, requirement, module}`. `advertised` is the exact
version a device may declare and what goes out in frame 1. `requirement` is
what a declared version is matched against, and is deliberately looser: a
device declaring `0.0.5` predates the advertisement and still has to be served.
`module` implements that version and nothing else — a module per version is
what keeps each one readable, rather than one module branching on payload
shape.

Old and new versions run side by side indefinitely. Devices in the field do not
upgrade in step with the platform, and some never upgrade at all.

## The extensions

The handshake above is shared by all of them. What an extension *says* once
attached is its own, scoped `<key>:<event>` in both directions.

| Key | What it carries | Contract |
| --- | --- | --- |
| `health` | Metrics, metadata and alarms, on a pace the platform sets | `NervesHub.Extensions.Health` |
| `metrics` | Numbers a device measures about itself, batched, on a pace the platform sets | [metrics.md](metrics.md) |
| `geo` | Device location | `NervesHub.Extensions.Geo` |
| `logging` | Log lines; batched from 0.1.0 | `NervesHub.Extensions.Logging` |
| `local_shell` | A shell on the device | `NervesHub.Extensions.LocalShell` |
| `network_identity` | Identities the device holds on networks NervesHub doesn't run | `NervesHub.Extensions.NetworkIdentity` |
| `error_reports` | Exceptions and explicit error reports, grouped into issues | [error_reports.md](error_reports.md) |

Most are documented by the module implementing them, which is enough while
`nerves_hub_link` is the only client that speaks them. An extension meant for
more than one client needs something a client author can work from without
reading Elixir. `error_reports` and `metrics` are those.

## Failure modes worth knowing

**A device declares a version the platform does not implement.** It resolves to
`Unsupported`, the key is left out of the attach list, and nothing is attached.
This is the correct answer and not a fallback: attaching the device to whichever
module was closest would have it sending messages nothing can read.

**A device sends a list of versions instead of a string.** `Version.parse/1`
raises on a non-binary and the extensions join fails entirely, taking every
other extension with it. The advertisement exists so no client needs to try.

**An extension raises while handling a message.** It is logged, reported to
Sentry and swallowed, so one misbehaving extension cannot take a device's
connection with it. Attach and detach are deliberately not rescued.
