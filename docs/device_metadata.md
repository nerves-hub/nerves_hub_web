# Device Metadata

Metadata is what a device says about itself rather than what it measures: where
it was installed, which customer it belongs to, the revision of the board under
it. It changes when the device is updated and at no other time.

This document is the message and what NervesHub does with it. It is written
down here because device clients implement against it. `nerves_hub_link` is the
reference client (`c:NervesHubLink.Client.device_metadata/0`, from 3.0.0).

## Why not the health report

Metadata used to ride every health report, which NervesHub asks for on a
timer. That sent the same unchanging map again and again, and tied a device's
metadata to the `health` extension being attached at all. So metadata is now a
message of its own on the device channel, sent when it is worth sending.

## The message

The device pushes `report_device_metadata` on its device channel (the `device`
topic):

```json
{"metadata": {"placement": "the shed", "board_revision": "c"}}
```

| Field | | |
| --- | --- | --- |
| `metadata` | required | An object of names to values. Strings are what the device page shows best; anything else is shown as Elixir prints it. |

There is no reply. It is named after `report_network_interface`, which is the
same kind of message: a fact about the device that NervesHub stores against the
connection.

**Send it once per join, not on a timer.** A connection starts with no metadata
against it, so a device sends it after every join, reconnects included. Send it
again only when the metadata changes while the device is connected
(`NervesHubLink.refresh_device_metadata/1` does this). A device with no
metadata sends nothing.

A payload without a `metadata` object (a list, a string, `null`, or no key at
all) is ignored and logged as an unknown message, and the connection carries
on. So is the whole message on a server that predates it, so a device can send
it without checking which server it is talking to.

## What NervesHub does with it

The map is **merged** into the `metadata` column of the device's connection
(`latest_device_connections`), so a message carrying only the keys that changed
leaves the rest alone. A key sent again replaces its old value. An empty map
changes nothing.

The column is the connection's, not the device's. A reconnect replaces the row,
and the metadata with it, which is why a device sends it on every join. The
same column holds a few keys the platform writes itself, such as
`device_api_version`, `connection_types` and `location` from the `geo`
extension. A device's metadata is merged beside them.

## Older devices

Firmware from before this message sends its metadata in the `metadata` key of
each health report instead. NervesHub goes on accepting it there, merged into
the same column the same way (`NervesHub.Extensions.Health`), so the device page
can't tell which path it came by. A device that sends `report_device_metadata`
should leave `metadata` out of its health reports.

## Where it shows

On the device page, under Metadata on the Details tab, sorted by name. Keys
that repeat the firmware's own metadata are left out, and so are empty values.
Every message is also kept in the device's Data History, as every device
message is.
