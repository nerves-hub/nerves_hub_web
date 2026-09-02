# Device Metrics

The `metrics` extension carries numbers a device measures about itself — CPU
temperature, memory used, load average, and whatever else its firmware knows how
to read. It is off by default and turned on per product, like every extension.

This document is the contract. `nerves_hub_link` is the reference client, but
nothing here is Elixir-shaped on purpose — the Rust agent and an ESP-IDF client
report through the same frames.

## Why not the health extension

The `health` extension already carries metrics. It carries them alongside device
metadata and alarms, in one report, which is the problem: the metadata is a blob
that changes when the device is updated and at no other time, and a device
reporting every minute sends it every minute. Across a fleet, most of what
health costs is the part that never changes.

Splitting the numbers out lets the two run at their own pace. A device that
attaches both should report health rarely — that is how often what health
carries actually changes — and metrics as often as anyone wants to watch them.

`health` goes on accepting metrics at 0.0.1. Every device in the field speaks
it, and both paths end in the same place on the server, so a client is free to
move over when it suits it.

## The frames

Negotiation is the shared handshake in
[extensions_protocol.md](extensions_protocol.md). Once attached, two frames
matter:

```text
server -> device   metrics:check    {}
device -> server   metrics:report   {"reports": [{..}, {..}]}
```

The platform decides when a device reports. A `check` goes out on one timer per
connection — however many people have the device's page open, the device is
asked once — every fifteen minutes while nobody is looking and every minute
while somebody is. The first interval is offset randomly, so a fleet that
connected together does not answer together.

A device may also report without being asked. The rate limit below is what keeps
that from being expensive.

### The report

```json
{
  "reports": [
    {
      "timestamp": "2026-09-02T11:04:00Z",
      "metrics": {"cpu_temp": 41.2, "mem_used_percent": 38.0, "load_1min": 0.42}
    },
    {
      "timestamp": "2026-09-02T11:05:00Z",
      "metrics": {"cpu_temp": 41.9, "mem_used_percent": 38.5, "load_1min": 0.51}
    }
  ]
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `timestamp` | yes | ISO 8601 with an offset. When the device took the readings. |
| `metrics` | yes | `{name: number}`. Names are yours; see the limits below. |

A report missing either field is skipped, and the rest of the batch is stored. A
device that gets one report wrong should not lose the others.

### Why a batch

A device that samples every ten seconds and reports every ten minutes gets to
keep all sixty readings, and a device that loses its connection gets to keep
what it measured while it was gone. Neither is possible if a message can only
carry the instant it was sent.

That is also why the readings carry their own timestamps. Almost everything else
in the protocol is stamped by the server, because the server saw it happen;
these it did not see.

A message may carry **60 reports**. Anything past that is dropped.

### Clocks

A reading is only worth what its timestamp is worth, and an embedded device
often has no idea what time it is until NTP settles. A timestamp more than **24
hours** from the platform's clock is treated as unreadable and the report is
skipped — there is no way to tell how late such a reading actually is, and a
chart that stretches to 1970 is worse than a gap.

A client with no clock at all should attach `metrics` only once its clock is
set, and use `health` until then.

## Rate limit

One message per second, with a burst of five, per device. One token per message
whatever the message carries — a batch of sixty readings costs exactly what a
batch of one costs, which is the point. Charging per reading would push a client
towards reporting more often, which is the opposite of what this is for.

The bucket is the extension's own, not shared with logging or error reports. A
device in trouble produces all three at once, and the moment they matter is the
wrong moment for them to starve each other.

An empty batch (`{"reports": []}`) costs nothing and stores nothing.

## Metric names

Names are yours to choose, and they are kept in a column type that is cheap
while a product reports a stable handful of them and expensive when it does not.
So a report is trimmed rather than trusted:

- A name longer than **64 bytes** is dropped.
- At most **20 names** per report are kept, in sorted order — so a device over
  the limit loses the same readings every time rather than an arbitrary subset
  that changes between reports. A deployment can raise this
  (`DEVICE_METRICS_MAX_KEYS_PER_REPORT`).
- A value that is not a number is dropped.
- Spaces are stripped from names.

In every case the rest of the report is stored, and the product's operators get
a notification saying what was discarded and by which device.

## What is stored

A report replaces the device's **latest set** — the numbers on its page, what
the devices list filters on, and what the advanced query's `metric:` comparisons
read. A metric the firmware has stopped collecting stops being shown. An older
report cannot move the latest set backwards, so a batch of buffered readings
arriving after a fresh one does not undo it.

Every reading is also kept as **history**, for the charts on the device's health
tab, and expires after **30 days**. Each historical reading records the firmware
the device was running when it took it, so a metric can be read per release:
whether memory use went up with 1.4.0, whether a temperature regression followed
a deploy. You do not send this, and should not: NervesHub takes it from the
firmware metadata your device reported when it connected.

History needs ClickHouse. A NervesHub deployment without one does not offer this
extension at all, and reports metrics through `health` — the latest set is
PostgreSQL either way, so the numbers, the filters and the queries all still
work; only the charts are missing.
