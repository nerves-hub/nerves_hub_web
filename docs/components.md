# Device Components

The `components` extension carries the things a device is connected to: a
microcontroller on a UART, Zigbee and Z-Wave nodes paired to its radio, a USB
peripheral. NervesHub calls each of these a **component**. It is off by default
and turned on per product, like every extension.

This document is the contract. `nerves_hub_link` is the reference client, but
nothing here is Elixir-shaped on purpose: the Rust agent and an ESP-IDF client
report through the same frames.

Version 0.1.0 is the inventory: which components a device has, what they are,
and which version of each thing they hold: their firmware, and any
configuration or model loaded onto them. It also carries what each component
measures and the state it is in (a lock being locked); see
[Readings and state](#readings-and-state). Updating what a component holds
comes in a later version. All of it builds on the identity defined here.

## The frames

Negotiation is the shared handshake in
[extensions_protocol.md](extensions_protocol.md). Once attached:

```text
server -> device   components:sync      {} or {"refresh": true}
device -> server   components:snapshot  {"components": [{"namespace": "zigbee", ..}, ..]}
device -> server   components:readings  {"reports": [..]}
device -> server   components:state     {"namespace": "zwave", "serial": "..", "state": "lock", "value": "unlocked", ..}
```

The last two are optional, and described under
[Readings and state](#readings-and-state). A device that only keeps an
inventory sends snapshots and nothing else.

The inventory has no per-component events. A device's components change rarely, a set
is easy to send whole, and a set can't drift the way a stream of events can: a
missed "removed" event would leave a component listed for ever. The platform
compares each snapshot with what it has stored and writes only what changed,
so sending the same set again costs a comparison and nothing more.

### `components:sync`

Sent as soon as the extension is attached, and again later when the platform
needs the set (see [Rate limit](#rate-limit)). A device must answer every one
with a snapshot.

```json
{}
```

```json
{"refresh": true}
```

`refresh` is set when a person asked, from the web UI, for the device to look
again. A device that can check on its components, such as pinging a Zigbee
node, should do so before answering rather than send what it last knew. A
device that can't just answers. Both are correct.

### `components:snapshot`

**Every** component the device currently has, reachable or not.

```json
{
  "components": [
    {
      "namespace": "mcu",
      "vendor": "raspberrypi",
      "model": "rp2350",
      "serial": "e6614c311b4a2c2f",
      "name": "Power controller",
      "vendor_name": "Raspberry Pi",
      "model_name": "RP2350",
      "address": "UART0",
      "versions": {"firmware": "1.4.2", "sensor_model": "2026.11"}
    },
    {
      "namespace": "zigbee",
      "vendor": "1286",
      "model": "SNZB-02D",
      "serial": "00:12:4b:00:2a:3f:91:c7",
      "name": "Freezer probe A",
      "vendor_name": "Sonoff",
      "hardware_revision": "B2",
      "versions": {"firmware": "2.1.0"},
      "last_seen_at": "2026-11-24T10:42:11Z"
    },
    {
      "namespace": "zwave",
      "vendor": "0129",
      "model": "8002:0600",
      "serial": "34028-23669-20938-46346-33746-07431-56821-14553",
      "name": "Office lock",
      "address": "node 9",
      "versions": {"firmware": "2.2.1", "keypad_config": "7"},
      "reachable": false,
      "last_seen_at": "2026-11-24T07:12:40Z"
    }
  ]
}
```

A device sends a snapshot when asked, and may send one at any time without
being asked. It should send one whenever its set or anything in it changes: a
component paired or removed, one that stops or starts answering, a new version
of anything one holds. Wait **five seconds** after a change before sending, so that pairing
twenty sensors in a row sends one snapshot rather than twenty.

`{"components": []}` says the device has none.

| Field | Required | Notes |
| --- | --- | --- |
| `namespace` | yes | What kind of component, and how to read `vendor`, `model` and `serial`. See [Namespaces](#namespaces). |
| `vendor` | yes | Who made it, as its protocol identifies them. |
| `model` | yes | What it is, as its protocol identifies it. |
| `serial` | yes | Which one it is, as a string that stays the same for this component. Unique within its namespace on this device. It needn't be a serial number: see [Components without a serial number](#components-without-a-serial-number). |
| `name` | no | What the device's application calls it ("Freezer probe A"). Shown in place of the model. |
| `vendor_name` | no | The maker's name, when the component says ("Sonoff", from a Zigbee node's Basic cluster). |
| `model_name` | no | The model's name, when the component says ("SNZB-02D"). |
| `hardware_revision` | no | A string. |
| `versions` | no | An object: what the component holds, and which version of each. See [Versions](#versions). |
| `address` | no | Where the component is on its bus ("UART0", "node 9", a USB port path). |
| `reachable` | no | `false` when the device has the component but couldn't reach it the last time it tried. Defaults to `true`. |
| `last_seen_at` | no | ISO 8601 with an offset. When the device last heard from the component. See [Timestamps](#timestamps). |

An optional field sent as an empty string counts as left out. Fields not
listed here are ignored, so a later version can add some without
breaking a platform that doesn't know them yet.

Together, `namespace`, `vendor` and `model` are the component's **model**. The
product's Components page groups by it, and later versions hang thresholds and
updates off it. `namespace` and `serial` are the component's identity on the
device.

### Versions

`versions` says what the component holds and which version of each. Each key
names one thing, written as a namespace is (lower case letters, digits and
`_`, starting with a letter, at most 32 characters), and each value is that
thing's version, as a string:

```json
"versions": {"firmware": "2.2.1", "keypad_config": "7"}
```

- **`firmware`** is the component's firmware, and the key every client uses
  for it. Pages show it as the component's firmware.
- **Any other key** is yours: a configuration file, a machine learning model,
  a calibration table. Pick a name and keep it, since a change of name reads
  as one thing removed and another added.

A version is stored as sent and compared exactly, never read as semver: plenty
of component firmware isn't, and a configuration may have no version scheme at
all. Report the version of everything a component holds, firmware or not.
When NervesHub sends updates to components, in a later version, an update
counts as done once the component reports the version it carried, so a
version NervesHub can't see is an update it can't confirm.

`versions` is optional, and so is every key in it, `firmware` included: a USB
peripheral or a Zigbee node that can't be asked for its firmware leaves it
out, and pages show no firmware for it. A version sent empty counts as left
out.

### What is rejected

A snapshot is rejected whole, and nothing stored changes, when:

- `components` isn't a list,
- it has more than **500** entries,
- any entry is missing a required field, or has one that is empty or isn't a
  string,
- any string is longer than **255 characters**, or `namespace` breaks the rule
  below,
- `versions` isn't an object, has more than **16** keys, has a key that breaks
  the namespace rule, or has a value that isn't a string, or
- two entries share a `namespace` and `serial`.

The set replaces what is stored, so applying the rest of a snapshot would mark
every entry that couldn't be read as gone. A rejected snapshot is logged on the
platform. Fix the client; resending the same snapshot gets the same answer.

## Namespaces

A namespace is lower case letters, digits and `_`, starting with a letter, at
most 32 characters. These have a convention, and should be used as written
whenever a component fits one:

| Namespace | `vendor` | `model` | `serial` |
| --- | --- | --- | --- |
| `mcu` | The chip maker, lower case: `raspberrypi`, `st`, `espressif` | The part, lower case: `rp2350`, `stm32g0b1` | The chip's unique ID, lower case hex |
| `zigbee` | Manufacturer code, 4 hex digits | The Basic cluster's model identifier, as the node sends it: `SNZB-02D` | IEEE address, `00:12:4b:00:2a:3f:91:c7` |
| `zwave` | Manufacturer ID, 4 hex digits | Product type and product ID, `8002:0600` | The node's DSK, `34028-23669-...`, or the home ID and node ID, `e3a177c2:9`, for a node without one |
| `ble` | Bluetooth SIG company identifier, 4 hex digits | Yours | The device address, `c4:5b:be:01:22:9f` |
| `usb` | Vendor ID, 4 hex digits | Product ID, 4 hex digits | The serial number string, or `address` when it has none |
| `custom` | Yours | Yours | Yours |

Hex is lower case with no `0x`, so the same component is written the same way
by every client.

A few of these are chosen to survive things a gateway does routinely:

- **Zigbee `model`** is the model identifier string every node answers with,
  not the image type it reports for firmware updates. Not every node supports
  updates, and every node has a Basic cluster. The image type comes in with
  updates, in a later version.
- **Z-Wave `serial`** is the DSK where the node has one: the key printed on an
  S2 device, which stays the same when the node is excluded and included again.
  A node ID doesn't, so a node without a DSK shows as a new component after
  it is included again. The old one goes Missing until somebody forgets it.

Any other namespace is accepted and shown as written, so a client doesn't have
to wait for the platform to report a new kind of component. Use `custom` until
a convention is agreed, rather than inventing a namespace two clients might
spell differently.

### Components without a serial number

Plenty of components have no serial number: an I2C sensor, a USB device that
doesn't report one, a microcontroller without a unique ID. `serial` is still
required, because it is how the platform tells one snapshot's components from
the next, and how a reading or state change names its component. Send the
first of these the component has:

1. A hardware ID: a serial number, a unique chip ID, a radio address.
2. Where it is on the device, when nothing else is connected there: the bus and
   address (`i2c-1:76`), a USB port path (`1-1.3`), a slot or connector name.
3. The application's own name for it, when the application knows which one it
   is: `freezer-probe-a`.
4. The model, when the device can only ever have one of it: a power
   controller soldered to the board, `rp2040`. A second one of the same model
   would need a `serial` of its own, and changing the first one's then makes
   it a new component, so don't use this where a second one could be added.

Whatever is sent becomes the component, so keep it the same for as long as
the component is the same one. A component sent under a new `serial` is a new
component, with no history, and the old one goes Missing until somebody
forgets it. That is why a hardware ID comes first: a sensor moved to another
port or renamed keeps it.

Never send a value that changes on its own, such as an index in a list, a
random ID made at boot, or a kernel device name like `ttyUSB0` that can swap
with another device on the next boot.

## Status

The platform works out each component's status from snapshots:

- **Working**: in the latest snapshot, and reachable.
- **Missing**: in the latest snapshot with `reachable: false`, or no longer in
  the snapshot at all. The web UI says which: "can't reach it" or "stopped
  listing it".

There is no way yet to say a component is reachable but faulty. Error and
Warning come in a later version.

A component that is no longer listed is kept, not deleted. A sensor whose
battery has died often drops out of its gateway's list, and the interesting
thing about it is where it was and when it went. If it is listed again it comes
back as the same component, with its history. A person can forget a Missing
component from the web UI; it comes back if the device lists it again.

A device keeps at most **1,000** components, listed or not. Past that, the
platform forgets the ones that have been missing longest. A device can't list
more than 500 at once, so only components it has stopped listing are ever
forgotten this way.

A device that disconnects keeps its components as they were. Its connection
status already says it has gone, and marking every component Missing at the
same time would bury whichever one actually failed. The snapshot on reconnect
corrects anything that changed.

The same `namespace` and `serial` on two devices are two components. A sensor
moved to another gateway shows on the new one, and as Missing on the old one
until somebody forgets it there.

## Timestamps

`last_seen_at` follows the rules in
[alarms.md](alarms.md#timestamps): a time more than **1 hour** ahead of the
platform's clock, or more than **72 hours** behind it, isn't believed. When a
snapshot has no believable time for a component, the platform keeps the last
one it had. Where it has none, the web UI shows when the device itself was last
seen for a working component, and when it went missing for a missing one.

A client that has no clock should leave `last_seen_at` out.

## Rate limit

One snapshot every ten seconds, with a burst of three, per device. The bucket
belongs to this extension alone.

A snapshot over the limit is dropped, and the platform sends `components:sync`
**thirty seconds** later. The snapshot that comes back carries whatever the
dropped one would have said. However many are dropped, only one sync is sent.

## What is stored

Each device's components are stored in PostgreSQL: identity, names, versions,
status, when each was first seen, when the device last heard from
it, and when it went missing. The device page's Components tab and the product's Components page read them. When
a snapshot changes something, an open device page updates straight away.

Each change is also recorded as **history** in ClickHouse: a component
appearing, going missing, coming back, changing the version of something it
holds, or being forgotten.
A snapshot that changes nothing records nothing. A NervesHub deployment without
ClickHouse keeps the current components and skips the history.

Turning the extension off for a product or a device stops new snapshots and
keeps what is stored.

## Readings and state

Besides being listed, a component can report two things:

- **Readings**: numbers it measures, such as a probe's temperature or a lock's
  battery. A stream, kept as history.
- **State**: named values that change now and then, such as a lock's `lock`
  being `locked`, `unlocked` or `jammed`. Every change is kept.

Neither changes a component's status, which stays Working or Missing. Both
are optional: a device sends them for the components that have them.

Readings and state changes name their component by `namespace` and `serial`.
A frame for a component the platform hasn't been sent in a snapshot is
ignored, and the platform sends `components:sync`, at most once every thirty
seconds, so the device can list it.

### State in a snapshot

A snapshot entry may also carry the component's current state. State then
can't drift: a change that was dropped, or made while the device was offline,
is put right by the next snapshot.

```json
{
  "namespace": "zwave",
  "vendor": "0129",
  "model": "8002:0600",
  "serial": "34028-23669-20938-46346-33746-07431-56821-14553",
  "name": "Office lock",
  "state": {"lock": "unlocked"}
}
```

`state` is `{state: value}` and replaces the component's stored state, so a
state left out is no longer shown. Leave the field out to say nothing about
state. Readings are never part of a snapshot.

### `components:readings`

```json
{
  "reports": [
    {
      "namespace": "zigbee",
      "serial": "00:12:4b:00:2a:3f:91:c7",
      "timestamp": "2026-11-24T10:40:00Z",
      "metrics": {"temperature": -18.9, "battery": 87}
    },
    {
      "namespace": "zigbee",
      "serial": "a4:c1:38:5e:20:7b:91:04",
      "timestamp": "2026-11-24T10:41:00Z",
      "metrics": {"co2": 1240, "temperature": 21.4, "humidity": 48}
    }
  ]
}
```

The rules are the ones [metrics.md](metrics.md) sets for a device's own
metrics, applied per component:

- One message may carry **60 reports**, for any mix of components. Send what
  the components measured since the last message, rather than one message per
  reading.
- A report missing a field is skipped, and the rest of the batch is stored.
- A `timestamp` more than **24 hours** from the platform's clock is unreadable,
  and the report is skipped.
- A metric name must match `^[a-z][a-z0-9_]{0,63}$`. At most **20** names per
  report are kept, in sorted order. A value that is not a number is dropped,
  and so is one larger than **10¹⁵** either side of zero.

Pick names a person can read, and the same names for the same quantity on
every model: `temperature` in degrees Celsius, `humidity` and `battery` in
percent, `co2` in ppm.

The platform keeps the latest value of each reading with the component,
merged from every report, so a component that reports its battery less often
than its temperature keeps both. A report older than the stored value of a
reading doesn't replace it. A component keeps at most **20** latest values,
the most recently reported.

### `components:state`

```json
{
  "namespace": "zwave",
  "serial": "34028-23669-20938-46346-33746-07431-56821-14553",
  "state": "lock",
  "value": "unlocked",
  "changed_at": "2026-11-24T09:41:00Z",
  "detail": "by keypad, user 3"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `namespace`, `serial` | yes | The component. |
| `state` | yes | What changed. Matches `^[a-z][a-z0-9_]{0,63}$`. |
| `value` | yes | What it is now. A string of at most 64 characters. |
| `changed_at` | no, but send it | ISO 8601 with an offset. Believed within **1 hour** ahead and **72 hours** behind the platform's clock, as in [alarms.md](alarms.md#timestamps), and otherwise replaced by the time the message arrived. |
| `detail` | no | Who or what changed it, shown beside the change. At most 255 characters. |

A component may have at most **8** states. Sending the value it already has
does nothing, so a device unsure whether a change arrived can send it again.
A change whose `changed_at` is older than the one stored for that state is
ignored too, so a retried change can't undo a newer one. A value set by a
snapshot has no time from the device, so any change replaces it.

### Rate limits for readings and state

- `components:readings`: one message a second, with a burst of five, per
  device. One token a message, whatever it carries.
- `components:state`: five a second, with a burst of twenty, per device. A
  change over the limit is dropped, and the platform sends `components:sync`
  thirty seconds later; the snapshot that comes back carries the state the
  dropped changes would have.
- Snapshots keep their own bucket, described under [Rate limit](#rate-limit).

### What is stored for readings and state

- The latest readings and current state of each component are kept in
  PostgreSQL with the component, for the lists and the side panel.
- Every reading is kept as history in ClickHouse for **30 days**, for the
  charts, with the device's firmware at the time.
- Every state change is added to the component's history in ClickHouse, which
  is kept for **90 days**.
