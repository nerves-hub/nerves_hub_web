# Device Alarms

The `alarms` extension carries a device's alarms as they are raised and cleared.
It is off by default and turned on per product, like every extension.

This document is the contract. `nerves_hub_link` is the reference client, but
nothing here is Elixir-shaped on purpose: the Rust agent and an ESP-IDF client
report through the same frames.

## Why not the health extension

The `health` extension already carries alarms. It carries them inside a report
the platform asks for on a timer, which is hourly while nobody is looking at the
device. An alarm raised just after a report is not heard about for up to an
hour, and one raised and cleared between two reports is never heard about at
all. Asking more often only swaps that delay for traffic, and most of what each
report carries has not changed since the last one.

An alarm is an event, and the device knows the moment it happens. So with this
extension the device sends it then, and the platform does not poll.

A device that attaches `alarms` should **leave the `alarms` key out of its
health reports**. `health` reads a missing key as "nothing to say about
alarms", so it leaves alone what `alarms` has stored. An empty `alarms` map
still means "none", and would clear them.

`health` goes on accepting alarms at 0.0.1. Every device in the field speaks it,
and both paths end in the same place on the server.

## The frames

Negotiation is the shared handshake in
[extensions_protocol.md](extensions_protocol.md). Once attached:

```text
server -> device   alarms:sync      {}
device -> server   alarms:snapshot  {"alarms": [{"alarm": "MyApp.HighTemp", ..}, ..]}
device -> server   alarms:raised    {"alarm": "MyApp.HighTemp", "description": "too hot", "raised_at": ".."}
device -> server   alarms:cleared   {"alarm": "MyApp.HighTemp", "cleared_at": ".."}
```

### `alarms:sync` and `alarms:snapshot`

Events alone drift. Anything raised or cleared while the device was offline was
never sent, and a missed clear leaves an alarm showing forever. So the platform
sends `alarms:sync` as soon as the extension is attached, and the device answers
with `alarms:snapshot`: **every** alarm it currently has raised.

```json
{
  "alarms": [
    {"alarm": "MyApp.HighTemp", "description": "too hot", "raised_at": "2026-09-24T02:11:09Z"},
    {"alarm": "MyApp.LowDisk", "description": "nearly full", "raised_at": "2026-09-23T18:40:00Z"}
  ]
}
```

Each entry has the same fields as an `alarms:raised` event, below.

The platform replaces what it has stored with that set: anything new is raised,
and anything stored that is missing is cleared. `{"alarms": []}` clears
everything. An entry without a usable `alarm` is skipped and the rest of the
set is applied, which means the platform treats that alarm as cleared.

`alarms:sync` goes out at other times too (see the rate limit below), and a
device must answer every one the same way. A device may also send a snapshot
without being asked.

### `alarms:raised`

```json
{"alarm": "MyApp.HighTemp", "description": "too hot", "raised_at": "2026-09-24T02:11:09Z"}
```

| Field | Required | Notes |
| --- | --- | --- |
| `alarm` | yes | The alarm's name. A string. |
| `description` | no | Shown next to the name. A string, or anything else, which is stored as its printed form. |
| `raised_at` | no, but send it | ISO 8601 with an offset. When the device raised the alarm. See [Timestamps](#timestamps). |

Raising an alarm that is already raised doesn't open a new episode. It updates
the description, and the time the alarm was first raised stays the same. So a
device that is unsure whether an event arrived can safely send it again.

### `alarms:cleared`

```json
{"alarm": "MyApp.HighTemp", "cleared_at": "2026-09-24T02:40:51Z"}
```

| Field | Required | Notes |
| --- | --- | --- |
| `alarm` | yes | The alarm's name. A string. |
| `cleared_at` | no, but send it | ISO 8601 with an offset. When the device cleared the alarm. |

Clearing an alarm that is not raised does nothing.

### Names

- A leading `Elixir.` is stripped, since that is how the Erlang alarm handler
  names a module alarm. `Elixir.MyApp.HighTemp` is stored and shown as
  `MyApp.HighTemp`.
- A name that is empty after that, or longer than **255 characters**, is
  ignored.

### Timestamps

Send `raised_at` and `cleared_at` whenever the device knows them. The device is
often the only one that does. An alarm raised during boot, before the device
connected, reaches the platform in the attach snapshot minutes later. One raised
while the device was offline for a day reaches it a day later. Dated by arrival,
every reconnect would look like the moment things went wrong.

Record the time when the alarm is raised, and keep it for as long as the alarm
stays raised, so every snapshot sends the same `raised_at` for it.

Device clocks are not always right. One that has not caught up with NTP can
say 1970, or the time its firmware was built. So the platform uses a time only
when it is believable:

- no more than **1 hour** ahead of the platform's clock, and
- no more than **72 hours** in the past, which covers a device that has been
  offline for a few days.

Otherwise, and when the field is missing or unreadable, the platform uses the
time the message arrived. Either way the event itself is applied: an alarm with
a doubtful time is still raised.

An alarm that is already raised keeps the time it was first raised, so a
snapshot can't move that time later, or earlier.

A client that has no clock should leave both fields out.

## Rate limit

One message per second, with a burst of ten, per device. A snapshot costs the
same as an event. The bucket belongs to this extension alone, not shared with
logging, metrics or error reports: a device in trouble produces all of them at
once.

A message over the limit is dropped. Dropping an alarm event is not like
dropping a metric reading, because a lost `cleared` means an alarm that stays
raised. So when the platform drops one, it sends `alarms:sync` **ten seconds**
later, and the snapshot that comes back corrects whatever the dropped events
would have changed. However many messages are dropped, only one sync is sent.

## What is stored

The device's currently raised alarms are stored in PostgreSQL, where the device
page, the devices list's alarm filter and the advanced query's `alarm` field all
read them. Whenever that set changes, an open device page updates straight away.

Each raise and each clear is also recorded as **history** in ClickHouse. A
NervesHub deployment without ClickHouse keeps the current set and skips the
history.

A device that disconnects keeps its alarms. What a device was reporting when it
went quiet is usually the interesting part, and the connection status already
says whether it is still there. On reconnect, the snapshot corrects anything
that changed while it was offline. An alarm that cleared while the device was
offline is recorded as cleared when the snapshot arrives, since a snapshot says
what is raised now and not when anything cleared.
