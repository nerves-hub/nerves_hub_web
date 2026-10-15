# Webhooks

An organization can send its devices' events to HTTP endpoints you run: a
device connecting or disconnecting, health and metrics reports, and the
progress and outcome of firmware updates. Each webhook sends the events of
every product in the organization, including products added later, or of the
products you choose. Webhooks are set up on the organization's
**Integrations** page, or through the [API](#managing-webhooks-with-the-api),
by members with the `manage` role.

This document is the contract for receivers. Event types and the shape of each
event's `data` only grow: keys may be added, and are never renamed or removed
without a new event type. Write receivers to ignore keys they do not know.

## Deliveries

Each event is a `POST` with a JSON body:

```json
{
  "type": "device.connected",
  "timestamp": "2026-10-13T09:41:07.123456Z",
  "data": {
    "org": { "name": "acme" },
    "product": { "name": "thermostat" },
    "device": { "identifier": "nh-0f1e2d", "firmware": { "...": "..." } },
    "connection": { "...": "..." }
  }
}
```

`timestamp` is when the event happened, not when it was sent. Every event
carries `org`, every event about a device carries `product` and `device`, so
one endpoint can serve several products.

Headers follow the [Standard Webhooks](https://www.standardwebhooks.com)
specification:

| Header | Value |
| --- | --- |
| `webhook-id` | The event's id, such as `msg_0199dd3c-…`. The same on every retry of the event. |
| `webhook-timestamp` | When this attempt was sent, in Unix seconds. |
| `webhook-signature` | `v1,` followed by the base64 HMAC-SHA256 signature. |
| `content-type` | `application/json` |
| `user-agent` | `NervesHub-Webhooks/1.0` |

Answer with any `2xx` status to accept a delivery. Only the status is read;
the body is ignored. Answer quickly and do the work afterwards: a delivery
that has not been answered within 15 seconds counts as failed.

### Verifying signatures

Each webhook has its own signing secret, shown (to members with the `manage`
role) as **Copy** beside the webhook. It looks like `whsec_` followed by
base64.

The signature is the HMAC-SHA256, keyed with the base64-decoded part of the
secret after `whsec_`, of:

```text
<webhook-id>.<webhook-timestamp>.<raw request body>
```

Sign the raw body exactly as received. Parsing the JSON and encoding it again
can change it and break the signature.

The Standard Webhooks libraries do all of this, including comparing in
constant time and refusing old timestamps. In Python, for example:

```python
from standardwebhooks.webhooks import Webhook

payload = Webhook(secret).verify(request.body, request.headers)
```

Or in JavaScript:

```js
import { Webhook } from "standardwebhooks";

const payload = new Webhook(secret).verify(rawBody, headers);
```

Without a library, check that `webhook-timestamp` is within a few minutes of
your clock, then compare your signature with each space-separated entry in
`webhook-signature` using a constant-time comparison.

**Send test event** on the Integrations page sends a `webhook.test` event to
the webhook straight away and shows how your endpoint answered. It is a good
way to check verification before subscribing to real events.

### Retries, ordering and duplicates

A delivery that fails (a status outside `2xx`, a timeout, or a connection
error) is retried after about 5 seconds, 1 minute, 5 minutes, 30 minutes and
2 hours. After the sixth attempt the delivery is dropped.

Redirects are not followed. A `3xx` counts as a failure; update the webhook's
URL instead.

Deliveries are **at least once** and **unordered**. A retry can arrive after
a later event, and in rare cases an event is delivered twice. Use
`webhook-id` to discard duplicates, and `timestamp` to order events.

### When an endpoint keeps failing

While an endpoint is failing, the Integrations page shows it as **Failing**
with the latest error. Deliveries in the 30 seconds after a failure are not
sent and count as failed attempts, so an endpoint that is down does not hold up
deliveries to other endpoints.

A webhook is turned off, and each product it was sending events for gets a
notification, when its endpoint:

- has accepted no delivery for 24 hours, or
- answers `410 Gone`, which tells NervesHub to stop.

Deliveries for a webhook that is turned off are dropped, not saved for later.
Turn it back on from the Integrations page once the endpoint is fixed.

### Where a webhook can point

URLs must be `https://` or `http://`, with no username or password. Use
`https://`: the signature proves where a delivery came from, but does not hide
its contents.

Unless the instance allows private destinations
(`WEBHOOKS_ALLOW_PRIVATE_DESTINATIONS`, see
[runtime configuration](runtime_configuration.md#webhooks)), webhooks can only
reach public addresses. Loopback, private, link-local and other reserved
addresses are refused, including host names that resolve to them.

## Events

A webhook subscribes to any of these. `webhook.test` is only sent on request.

| Type | When |
| --- | --- |
| `device.connected` | A device finished connecting and is online. |
| `device.disconnected` | A device's connection closed, or NervesHub closed it after the device stopped sending heartbeats. |
| `device.health_reported` | A device sent a health report. |
| `device.metrics_reported` | A device sent a batch of metrics readings. |
| `device.health_status_changed` | A device's health status moved, such as from healthy to warning. |
| `device.firmware_update.scheduled` | An update was sent to a device. |
| `device.firmware_update.progress` | A device reported how its update is going. |
| `device.firmware_update.finished` | A device's update attempt ended. |
| `device.firmware_validated` | A device confirmed that its firmware is good. |

### The device

Every device event's `data.device` identifies the device and the firmware it
is running, as far as NervesHub knows:

```json
{
  "identifier": "nh-0f1e2d",
  "firmware": {
    "uuid": "6bb3bf62-4d9a-5a21-9a8b-38e6e8c8f6d1",
    "version": "1.4.2",
    "platform": "rpi4",
    "architecture": "arm"
  }
}
```

`firmware` is `null` for a device that has never reported its firmware. Below,
`device`, `org` and `product` are left out of each example.

### `device.connected`

```json
{
  "connection": {
    "id": "0199dd3c-2f6e-7b1a-9d0e-3c5c2a1b4f00",
    "established_at": "2026-10-13T09:41:06.871203Z"
  }
}
```

`connection.id` is the same in the matching `device.disconnected`.

### `device.disconnected`

```json
{
  "connection": {
    "id": "0199dd3c-2f6e-7b1a-9d0e-3c5c2a1b4f00",
    "established_at": "2026-10-13T09:41:06.871203Z",
    "disconnected_at": "2026-10-13T11:02:44.510022Z",
    "reason": null
  }
}
```

`reason` is `"Stale connection"` when NervesHub closed a connection whose
device had stopped sending heartbeats, which is how a device that lost power
or network is noticed. Otherwise it is `null`.

### `device.health_reported`

```json
{
  "metrics": { "cpu_temp": 47.2, "mem_used_percent": 31.0 },
  "alarms": { "Elixir.MyApp.DiskFull": "/data is 97% full" },
  "metadata": { "site": "north-yard" }
}
```

`metrics` are the readings NervesHub stored: numbers only, as floats. Names
longer than 64 bytes and readings past the instance's per-report limit
(20 by default) are left out. `alarms` and `metadata` are passed on as the
device sent them.

By default, devices send a health report every hour, and every minute while
somebody has the device's page open.

### `device.metrics_reported`

```json
{
  "reports": [
    { "timestamp": "2026-10-13T09:40:00Z", "metrics": { "fps": 59.0 } },
    { "timestamp": "2026-10-13T09:41:00Z", "metrics": { "fps": 60.0 } }
  ]
}
```

Only devices using the metrics extension send these; other devices include
their metrics in health reports. Each report's `timestamp` is when the device
took the readings. Reports NervesHub did not store, such as one whose
timestamp is more than a day from NervesHub's clock, are left out.

### `device.health_status_changed`

```json
{
  "status": "unhealthy",
  "previous_status": "healthy",
  "reasons": {
    "warning": {},
    "unhealthy": {
      "cpu_usage_percent": {
        "value": 75,
        "threshold": 90.0,
        "operator": "gte",
        "period_seconds": 3600,
        "aggregation": "share"
      }
    }
  }
}
```

`status` and `previous_status` are each one of `unknown`, `healthy`,
`warning` or `unhealthy`, judged against the product's health profile each
time the device reports. `previous_status` is `null` the first time a device
is judged.

`reasons` names each metric holding the device at `warning` or `unhealthy`,
with the threshold in force at the time, and is `null` when nothing is
engaged. With an `aggregation` of `share`, `value` is the percentage of the
measurement period's readings that crossed the threshold; with `count`, it is
a number of occurrences, such as disconnects. On an instance without an
analytics database, or a product without a health profile, devices are judged
on their latest readings alone, and their reasons carry only `value` and
`threshold`.

The event is sent when the status changes. A device that stays at `warning`
while the metric holding it there changes sends nothing.

### `device.firmware_update.scheduled`

```json
{
  "firmware": { "uuid": "1d9e47a8-…", "version": "1.5.0" },
  "initiated_by": "deployment_group",
  "deployment_group": { "name": "production" }
}
```

`initiated_by` is `"deployment_group"`, `"user"` for an update a person sent
from NervesHub, or `"device"` for a device that manages its own updates and
asked for one. `deployment_group` is `null` for an update a person sent.

### `device.firmware_update.progress`

```json
{
  "status": "downloading",
  "progress": 42,
  "firmware": { "uuid": "1d9e47a8-…", "version": "1.5.0" }
}
```

`status` is one of `received`, `started`, `downloading`, `updating` or
`completed`. `completed` means the firmware is installed and the device is
about to restart into it; the update has not finished until the device comes
back on it. `progress` is a percentage for `downloading` and `updating`, and
otherwise `null`. While a device downloads, an event is sent when the stage
changes and then at most every 15 seconds. `firmware` is the firmware being
installed.

### `device.firmware_update.finished`

```json
{
  "outcome": "failed",
  "reason": "fwup error: signature verification failed",
  "source_firmware": { "uuid": "6bb3bf62-…", "version": "1.4.2" },
  "target_firmware": { "uuid": "1d9e47a8-…", "version": "1.5.0" },
  "deployment_group": { "name": "production" }
}
```

| `outcome` | Meaning |
| --- | --- |
| `succeeded` | The device came back running the new firmware. |
| `failed` | The device reported that the update failed. |
| `ignored` | The device declined the update. |
| `rescheduled` | The device asked for the update to be sent again later. |
| `expired` | The device stopped reporting progress for 30 minutes. |
| `abandoned` | The device reconnected still running its old firmware, without saying why. |

`reason` is whatever the device said, if anything, cut to 200 characters.
`source_firmware`, `target_firmware` and `deployment_group` are `null` when
not known, and a firmware's `version` is `null` once it has been deleted.

### `device.firmware_validated`

The device marked the firmware it is running as good, typically after
restarting into a new update and passing its own checks. There is nothing
beyond `device`.

### `webhook.test`

Sent only by **Send test event**, to the one webhook being tested. It is about
the webhook rather than a device, so it carries `org` and no `product` or
`device`.

```json
{
  "message": "A test event sent by Jane Doe from NervesHub."
}
```

## Managing webhooks with the API

An organization's webhooks can also be managed through the NervesHub API,
under `/api/orgs/{org_name}/webhooks`. Every endpoint needs
the organization `manage` role, reading included, because a webhook's URL can
carry the receiver's credentials. The full request and response schemas are
in the API documentation at `/api/docs`, under **Webhooks**.

| Request | Does |
| --- | --- |
| `GET /webhooks` | Lists the organization's webhooks. |
| `POST /webhooks` | Adds one, from `url`, `events` and optionally `description`, `products`, `all_products` and `enabled`. |
| `GET /webhooks/{id}` | Gets one, with its delivery state (`failing_since`, `last_error`, `disabled_reason`). |
| `PATCH /webhooks/{id}` | Changes `url`, `description`, `events`, `products`, `all_products` or `enabled`. |
| `DELETE /webhooks/{id}` | Removes it. |
| `POST /webhooks/{id}/regenerate_secret` | Replaces the signing secret. |
| `POST /webhooks/{id}/test` | Sends a `webhook.test` event and returns `delivered`, `status` and `error`. |

Products are named, as in the rest of the API. A webhook with
`"all_products": true` (the default) sends every product's events, including
products added later. To send only some, pass `"products": ["thermostat",
"doorbell"]`: naming products sets `all_products` to `false` unless the request
says otherwise. Responses list the products in `products`, which is empty for
a webhook sending every product's events.

The signing secret is only returned by `POST /webhooks` and
`regenerate_secret`, never when listing or getting a webhook. A caller that
has lost it regenerates it.
