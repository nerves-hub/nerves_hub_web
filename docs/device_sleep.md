# Devices That Sleep

A battery device, such as an ESP32 running `nerves-hub-link-esp32`'s
`Agent::run_session`, cannot hold a connection open. It wakes, connects,
reports, and goes back to sleep. Without being told, NervesHub sees only that
its connection closed, and shows it the same way it shows a device that lost
power: offline, and if the radio dropped without closing the socket, a stale
connection. Every wake also counts toward flapping in Insights and toward the
"disconnects" health metric.

A device that says it is going to sleep is shown as asleep instead, with when
it is due back, and its sleep is left out of those counts.

This document is the message and what NervesHub does with it. It is written
down here because device clients implement against it.

## The message

Before it sleeps, the device pushes `sleeping` on its device channel:

```json
{"mode": "deep", "duration_ms": 300000}
```

| Field | | |
| --- | --- | --- |
| `mode` | optional | `"deep"` or `"light"`. Anything else, or nothing, is taken as `"deep"`. It is shown to people and makes no other difference. |
| `duration_ms` | optional | How long it will sleep, in milliseconds. Leave it out, or send `null`, for a device that waits for something else to wake it (a GPIO, the ULP). |

There is no reply. Send it, then close the socket as you normally would. A
device that sleeps without closing the socket is still recorded as asleep:
the connection closes when its heartbeats stop, and keeps the reason.

**Send a duration, not a time.** A device that has just woken may not have its
clock set. NervesHub works out when to expect it from when the message
arrived. A duration of zero or less, one that is not a whole number, or one
over 366 days is recorded as a sleep with no time given.

`rebooting`, which `nerves_hub_link` already sends before it reboots, is
recorded the same way, as a reboot, with no wake time.

A server that predates this message logs it as unknown and carries on, so a
device can send it without checking which server it is talking to.

## What NervesHub does with it

The reason and the wake time are written to the device's connection
(`latest_device_connections`) when the message arrives, before the socket
closes. The connection stays connected until it does, so a console, a script
or an update can still reach it.

| Column | |
| --- | --- |
| `disconnected_reason` | `light_sleep` or `deep_sleep` (see `NervesHub.Devices.DisconnectReason` for every reason) |
| `expected_wake_at` | when the device said it would be back, or null |
| `wake_missed_at` | reserved for marking a device that did not come back; not yet set |

When the device wakes and connects again, the new connection replaces the row,
and the three columns are cleared with it. `device_connection_history` in
ClickHouse keeps the reason and `expected_wake_at` for every connection.

## Overdue

An ESP32 without a 32 kHz crystal times its sleep with an RC oscillator that
drifts by several percent. So a device counts as overdue only once it is later
than it said by two minutes, or a tenth of how long it slept, whichever is
longer: a five-minute sleep has until seven minutes, a ten-hour sleep until
eleven hours.

## Where it shows

- **Device page**: two rising z's take the status dot's place, green while
  asleep and orange once overdue, and the line beside the identifier reads
  "Asleep back in 5 minutes" or "Overdue was due back 20 minutes ago", with
  the expected time in its tooltip. A device that has said it is going to
  sleep but not yet closed its connection reads "Online … going to sleep".
- **Devices list**: the same z's in place of the dot, with the sentence in
  their tooltip, "Asleep, 5 minutes left" or "Overdue 20 minutes" in the
  Connection column, and an "Asleep" choice in the Connection filter
  (`connection = "asleep"` in the query bar). It matches overdue devices too.
  Every row's dot keeps the z's width, so identifiers line up. The side panel
  a row opens shows the z's and the device page's line, and its Reboot button
  says the device is asleep rather than offline.
- **API**: a device's `sleep` field, `{"state", "mode", "expected_wake_at"}`,
  is set from when the device says it is going to sleep until it connects
  again, and is null otherwise.
- **Webhooks**: `device.disconnected` carries `reason_code` and
  `expected_wake_at`; see [webhooks](webhooks.md#devicedisconnected).
- **Insights and health**: a connection that ended in sleep does not count
  toward flapping or the "disconnects" metric. Nor do reboots, reconnects
  someone asked for, revoked keys, or server restarts.
