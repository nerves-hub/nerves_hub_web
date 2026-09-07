# Device-Managed Updates

Some devices should not be updated whenever their deployment group decides.
A machine mid-cycle, a vehicle in motion, a device whose owner has been given a
say — each needs to choose *when* it takes firmware. None of them should get to
choose *what* firmware, and none of them should be able to make themselves
unreachable.

This document is the protocol and the rules around it. It is written down here
because `nerves_hub_link` and the other clients implement against it, and the
only other statement of it would be one client's source.

## The mode

Every device has an `update_mode`, and it is the whole answer to how that device
receives firmware.

| Mode | Orchestrator pushes | Device may pull | Manual push |
| --- | --- | --- | --- |
| `automatic` | yes, on the deployment's schedule | yes, if eligible | yes |
| `device_managed` | never | yes, if eligible | yes |
| `off` | never | never | yes |

Three things hold across all of them.

**The deployment group always names the target firmware.** `device_managed` is
not "the device picks a build" — it is "the device picks a moment". A
device-managed device stays in its deployment group and is excluded from pushes,
not from firmware resolution.

**A manual push always lands.** This is the remote fix-it button, and it has to
work on a device whose own scheduling logic is the thing that is broken. Pushing
firmware by hand pauses automatic updates so the deployment does not immediately
overwrite what was just sent — but only for an `automatic` device. The other two
modes are not pushed to anyway, so there is nothing to pin, and freezing them
would cost a mode somebody chose.

**Pulling is gated on eligibility, not on mode.** `request_update` hands out a
signed URL for firmware the deployment group has already designated for that
device; under `automatic` the server was going to send that same URL later
anyway. A device in a staged rollout that has not reached its wave is refused
whatever its mode.

## The grant

`update_mode` carries the state. `managed_updates_allowed` carries the
capability: whether a device may put *itself* into `device_managed`. It defaults
to `false`, so self-management is opted into rather than arrived with.

Two rules bound what a device may do to itself, and it needs to pass both:

- **`off` is the operator's alone.** A device can neither freeze itself out of
  reach nor unfreeze itself.
- **`device_managed` needs the grant.**

An operator setting either from the dashboard or the API is always allowed — the
grant is about what a device may do, not what a person may do. Revoking it does
not move a device that is already `device_managed`; dragging a fleet back into
rollout is an explicit call, never a side effect.

Every change is audited, with the device itself as the actor when the device is
the one that asked.

## Messages

On the `device` topic.

`device_api_version >= 2.4.0` gates what the server sends *unasked*: a device
below it is never sent `update_mode` on join or on change, because an older
client would log it as unknown and do nothing. It does not gate what the server
accepts. The version is self-reported and every handler enforces its own rules
regardless, so a device that sends one of these messages is answered — including
the reply to `set_update_mode`, because acting on a request without answering it
is exactly how a device and the server end up disagreeing.

```text
server -> device   update_mode       {"mode": "automatic", "managed_updates_allowed": false}
device -> server   check_update      {}
server -> device   update_available  {"available": true, "firmware_meta": {..}}
device -> server   request_update    {}
server -> device   update            (the existing message, unchanged)
server -> device   update_rejected   {"reason": "busy", "delay_for": 5}
device -> server   set_update_mode   {"mode": "device_managed"}
```

**`update_mode`** is sent when the device joins, whenever the mode or the grant
changes underneath it, and as the answer to `set_update_mode`. An operator can
flip either at any time, and a device that only learned them at join would show
a stale switch until it reconnected.

**`check_update`** is allowed in every mode, including `off` — it is read-only,
and it lets a frozen device tell its user that an update exists and an
administrator needs to act. It reports firmware metadata and **no URL**.

**`request_update`** is the one that mints a URL. On success the answer is the
existing `update` message, so a device-initiated update introduces no new
firmware-application path on the device: everything after the URL arrives is
code that already shipped. On refusal the answer is `update_rejected`.

**`set_update_mode`** is always answered with `update_mode` carrying the mode the
device actually has now, refusal included. A device and the server can never end
up disagreeing about whether the device is being pushed to.

### Why check and request are separate

Two reasons, either of which would be enough.

Firmware URLs are signed and time limited. A device that checks at 02:00 and
updates at 04:00 would find a dead link, so the URL is fetched at the moment it
is about to be used.

And they carry different gates: `check_update` is allowed everywhere,
`request_update` is refused under `off`.

## Firmware too old to manage itself

A `device_managed` device that connects reporting `device_api_version < 2.4.0`
is returned to `automatic`, with an audit entry naming the device as the actor.

Left alone it would be stranded: the orchestrator does not push to a
`device_managed` device, its firmware cannot ask, and it is never sent
`update_mode` because that is gated on the same version — so it would not even
know. The sharp case is a firmware auto-revert, where a failed update drops a
device back onto an image that predates the feature, exactly when being stuck
matters most.

The trade is deliberate and worth knowing about: a fleet deliberately set to
`device_managed` that has not yet rolled out firmware supporting it will be
moved to `automatic` as its devices connect, and will start receiving pushes.
**Roll the firmware out first, then set the mode.**

An operator can set the mode back once the device is running firmware that can
manage itself. Nothing here reverses automatically — the mode is the operator's
to choose, and guessing that a device wanted its old mode back would be guessing
about a device we could not talk to at the time.

## Pacing

Deployment groups pace rollouts, and a self-scheduling fleet would walk straight
past that — ten thousand units waking at 03:00 local all ask at once.

So a device-initiated request takes a concurrency slot exactly as an
orchestrator-driven update does. When the deployment has none free the device is
told to come back later rather than refused outright:

```text
update_rejected  {"reason": "busy", "delay_for": 5}
```

`delay_for` is in minutes. A client should treat any `update_rejected` as
"not now" rather than "not ever", and must not retry faster than `delay_for`.

## Where this lives

- `NervesHub.Devices.Updates` — the mode, the grant, and `check_update/1`
- `NervesHub.DeviceEvents.device_requested_update/1` — the pull, including pacing
- `NervesHub.DeviceLink` — the message handlers
- `NervesHub.Devices.Device` — `update_mode` and `managed_updates_allowed`

`updates_enabled` is gone as a column concept but survives in the JSON API,
derived as `update_mode != :off`, so existing consumers are unbroken. The
advanced query language keeps `updates = "enabled"` and `"disabled"` with their
old meanings and gains `"automatic"` and `"device-managed"`.
