# Device Error Reports

The `error_reports` extension carries exceptions, exits and explicit error
reports from a device to NervesHub, where they are grouped into issues you can
resolve. It is off by default and turned on per product, like every extension.

This document is the contract. `nerves_hub_link` is the reference client, but
nothing here is Elixir-shaped on purpose — the Rust agent and an ESP-IDF client
report through the same frames.

## Why not the logging extension

A crash already produces log lines, so the obvious question is why this is not
a filter over those.

Log lines are text, and text does not group. Two occurrences of the same bug
differ by a pid, a timestamp and a line of formatting, so counting them means
counting strings, which counts noise. Log lines are also kept for three days,
because that is the right retention for a firehose and the wrong retention for
"has this been happening since the March release?"

An error report is structured where it needs to be — a kind, a reason, frames —
so the server can decide that two of them are the same bug. That decision is
what the whole feature rests on, and it is not one that can be made over
formatted text.

## The frames

Negotiation is the shared handshake in
[extensions_protocol.md](extensions_protocol.md). Once attached, one frame
matters:

```text
device -> server   error_reports:report   {"reports": [{..}, {..}]}
```

Nothing goes the other way. The platform does not poll for errors and does not
acknowledge them; a device that has nothing to report sends nothing.

### Why a batch

A supervisor restart storm produces a burst of crashes in the same second, and
those bursts are the interesting ones. NervesHub rate-limits how *often* a
device may send, not how much it may say, so a batch of twenty-five reports
costs the same one token as a batch of one. A client that sends one report per
message throws away most of a crash loop to the limiter and keeps an arbitrary
sample of it.

This is the same bargain [the logging extension](extensions_protocol.md) makes
at version 0.1.0, and for the same reason. It is why `error_reports` starts at
0.1.0 with no single-report version behind it.

## A report

```json
{
  "timestamp": "2026-08-31T10:22:31.123456Z",
  "kind": "error",
  "reason": "** (RuntimeError) connection refused",
  "message": "GenServer MyApp.Worker terminating\n** (RuntimeError) ...",
  "source": "logger",
  "frames": [
    {"module": "MyApp.Worker", "function": "handle_info/2",
     "file": "lib/my_app/worker.ex", "line": 42}
  ],
  "context": {
    "queue": "uploads",
    "uptime_ms": "987654",
    "reboot_count": "3",
    "free_memory_bytes": "12345678"
  },
  "firmware_uuid": "d1e2f3a4-..."
}
```

**Required:** `timestamp`, `kind`, `reason`. A report missing any of them is
dropped, and its neighbours in the batch are kept — one malformed report should
not cost a device the rest of its second.

| Field | Type | Notes |
| --- | --- | --- |
| `timestamp` | ISO 8601 string | When the device saw it, not when it sent it. May also be given as `meta.time` in microseconds, matching the logging extension. A report the server timestamps on arrival would claim the device crashed whenever the network got around to delivering it. |
| `kind` | string | `error`, `exit`, `throw`, `panic`, or whatever your runtime calls it. Free text, matched literally. |
| `reason` | string | One line. The exception and its message, not the stacktrace. Capped at 2 KB. |
| `message` | string | The full formatted report, if you have one. Capped at 8 KB. |
| `source` | string | `logger` for something caught automatically, `manual` for an explicit report. Defaults to `logger`. |
| `fingerprint` | string | A grouping key of your own. See [Grouping](#grouping) — supply this only when you know better than the server does. |
| `frames` | array | Innermost first. Capped at 30; the rest are dropped, because a fingerprint reads the top three and a person reads maybe twenty. |
| `context` | object | Free string-to-string map, and where device vitals go. Capped at 32 keys, 512 bytes per value. Values under credential-shaped keys are redacted server-side. |
| `firmware_uuid` | string | Which firmware was running. The platform fills this in from the connection when you omit it. |

### Device vitals go in `context`

Uptime, reboot count, free memory — whatever your runtime can say about its own
state at the moment of the error — are context entries, not fields of their own:

```json
"context": {"uptime_ms": "987654", "reboot_count": "3", "free_memory_bytes": "12345678"}
```

Those three are what a BEAM device happens to have. A device with free heap and
a signal strength to report instead sends those under its own names and nothing
on the server changes. Keys named `uptime_ms`, `free_memory_bytes` and
`reboot_count` are given friendly labels and units in the UI; everything else
renders as it arrived.

`firmware_uuid` is the exception, and is a field. It answers "which release
broke this", it is carried on the issue as well as the occurrence, and the
platform fills it in from the device's connection when a report omits it — none
of which is true of the rest.

Vitals are what turn a stacktrace into something you can act on. "Does this only
happen on devices that have been up for a week" is a question a fleet operator
asks, and it is not answerable from a stacktrace.

### A frame

```json
{"module": "MyApp.Worker", "function": "handle_info/2",
 "file": "lib/my_app/worker.ex", "line": 42}
```

Every field is optional and every field is a string except `line`. `module` is
a namespace, `function` a name — nothing here is a BEAM MFA. A Rust client
sends:

```json
{"module": "nerves_hub_link::agent", "function": "run_loop",
 "file": "src/agent.rs", "line": 88}
```

and every server path works unchanged.

## What the server does with it

1. **Validates and caps.** Anything over the limits above is truncated, and the
   original size is recorded so the UI can say how much was dropped rather than
   silently showing a fragment.
2. **Fingerprints.** See below.
3. **Writes the occurrence** to ClickHouse, through the same batching buffer
   that carries log lines and connection history.
4. **Upserts the group** in PostgreSQL — count, last seen, last firmware — and
   reopens it if it had been resolved.

## Grouping

Two occurrences of one bug have to land on one issue, or the product page is a
firehose with extra steps. The fingerprint is what decides that, and it is
computed **on the server**:

```
sha256(version <> kind <> normalize(reason) <> top three frames)
```

`normalize` strips the parts that differ between two instances of the same
bug — pids, refs, hex addresses, long digit runs, UUIDs — so
`** (RuntimeError) timeout after 5000ms in #PID<0.412.0>` and the same thing at
`#PID<0.918.0>` are one issue.

The frame part is module and function only. **Line numbers are deliberately
excluded:** a line moves when the file above it changes, and an issue that
splits on every unrelated edit is worse than no grouping at all.

### Why the server and not the device

One rule, in one place, revisable without a firmware release. Fingerprinting is
the part of this feature most likely to need adjustment after seeing real data,
and adjusting it should not mean waiting for a fleet to update.

The stored `fingerprint_version` is what makes revision safe: bumping it means
new occurrences group into new issues rather than silently re-grouping history.
A revision does not apply retroactively, so history splits at the version
boundary — expect that, rather than discovering it.

### When to send your own

Supply `fingerprint` when the application knows something the stacktrace does
not. Every failure in a payment integration might come through one HTTP client
function, and grouping them by that frame tells you nothing; grouping them by
`"payment-gateway"` tells you the integration is down. A supplied fingerprint
wins outright.

## Lifecycle

An issue is **unresolved**, **resolved** or **muted**.

- **Resolve** when you have shipped a fix. If it happens again, it reopens and
  is marked as regressed.
- **Mute** when you know about it and do not want it in the queue. A muted
  issue keeps counting and does not reopen.

The reopen rule is currently blunt: any occurrence after the issue was resolved
reopens it. On a fleet where half the devices are still running the firmware
that had the bug, that means it reopens straight away, and mute is the right
answer there. A firmware-aware rule — reopen only for occurrences on firmware
built after the fix — is the intended refinement.

## Retention

Occurrences are kept for **30 days**, against three days for log lines. An
error you look into a week later is ordinary; a log line you look at a week
later is not.

The window is a ClickHouse TTL set when the table is created, not a runtime
setting. There is no environment variable for it deliberately: a variable read
at migration time would apply to fresh installations and quietly do nothing on
existing ones, which is worse than having no knob at all. An operator who wants
a different window changes it directly, and it takes effect for rows already
stored:

```sql
ALTER TABLE device_error_reports
  MODIFY TTL toDateTime(timestamp) + toIntervalDay(90);
```

The issue outlives its occurrences. Counts and first-seen survive the TTL, so
"this has happened forty thousand times since March" stays answerable long
after the March occurrences are gone.

## Writing a client

**Attach and then wait.** There is nothing to set up on attach and nothing is
requested. Report when something breaks.

**Catch crashes with a log handler.** On the BEAM that is a `:logger` handler
filtering for crash reports, reading the exception, exit reason and stacktrace
out of the report metadata. Elsewhere, whatever your runtime offers — a panic
hook, an unhandled-exception handler.

**Offer an explicit call too.** Application code frequently catches an error,
handles it, and still wants it reported with context the stacktrace does not
carry. `NervesHubLink.report_error(exception, context: %{}, group: nil)` is the
reference shape.

**Buffer locally and send a batch.** Collect for a second, then send. Cap what
you hold, and if you drop reports, say so in a report of its own — a gap
somebody can see beats a gap they cannot.

**Do not report your own failures through this.** A client whose reporting path
raises and reports that raise is a loop with a rate limiter as its only brake.

**Expect to be limited.** The bucket refills at one message per second with a
burst of five, and a message carries at most twenty-five reports. Past that the
message is dropped, not queued. Hold your buffer across the drop and send it
with the next one.
