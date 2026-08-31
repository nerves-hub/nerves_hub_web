# Runtime configuration

Everything in [`config/runtime.exs`](../config/runtime.exs) is read when the
release boots, so it can be changed by restarting a node rather than rebuilding
an image. This document lists the environment variables it reads, their
defaults, and what they do.

A few conventions used below:

- **Prod only** marks a variable that is only read when `MIX_ENV=prod`. In
  `dev` and `test` the equivalent setting comes from `config/dev.exs` or
  `config/test.exs` and the variable is ignored.
- **Required** marks a variable read with `System.fetch_env!/1` — the node
  refuses to boot without it (in the cases where it applies at all).
- Boolean variables are compared against the exact string `"true"`. Anything
  else, including `"1"` and `"TRUE"`, counts as false.
- Integer variables are parsed strictly. A non-numeric value crashes the boot.

## Minimum production configuration

A single-node deployment serving both the dashboard and devices needs:

```
SECRET_KEY_BASE=...
LIVE_VIEW_SIGNING_SALT=...
HOST=mynerveshub.com
DATABASE_URL=postgres://...
```

plus a TLS key and certificate for the device endpoint (see
[Device endpoint](#device-endpoint)) and, if you are not storing firmware on
local disk, the [S3 settings](#firmware-and-archive-uploads).

## Application role

A production cluster is asymmetric: device nodes terminate device socket
connections, web nodes serve the dashboard, API and CLI and run the deployment
orchestrators. `NERVES_HUB_APP` picks which supervision tree a node starts.

| Variable | Default | Description |
| --- | --- | --- |
| `NERVES_HUB_APP` | `all` | One of `all`, `web`, `device`. Any other value raises at boot. `all` runs both roles in one node, which is the usual choice for a self-hosted instance. |
| `DEPLOY_ENV` | the Mix env | Free-form name for the deployment. Used as the Sentry environment name. |

## Web endpoint

Prod only. Configures `NervesHubWeb.Endpoint`, and is only read when
`NERVES_HUB_APP` is `all` or `web`.

| Variable | Default | Description |
| --- | --- | --- |
| `WEB_HOST` / `HOST` | — (**required**) | Hostname the dashboard is served on, e.g. `mynerveshub.com`. `WEB_HOST` wins; boot raises if neither is set. |
| `HTTP_PORT` / `PORT` | `4000` | Port the HTTP listener binds to. |
| `WEB_PORT` | `443` | Port used when generating URLs. Set this when a proxy terminates TLS on a different port than the one the app binds. |
| `WEB_SCHEME` | `https` | Scheme used when generating URLs. |
| `SECRET_KEY_BASE` | — (**required**) | Phoenix secret key base. Generate with `mix phx.gen.secret`. |
| `LIVE_VIEW_SIGNING_SALT` | — (**required**) | LiveView signing salt. |
| `WEB_FORWARDED_IP_HEADER` | `x-forwarded-for` | Header carrying the address a device connected from, for devices that reach the web endpoint rather than the device endpoint. TLS is terminated ahead of this endpoint, so the socket's peer is whatever terminated it. Must start with `x-`, because Phoenix passes a socket only those headers — Fly's `fly-client-ip` never arrives and raises at boot if named. Set to `none` when the endpoint is exposed directly, since nothing is overwriting the header there and it holds whatever the device chose to send. |
| `WEB_FORWARDED_IP_TRAILING_HOPS` | `0` | How many entries at the end of that header were added by infrastructure rather than by the device. The address is counted from the right, so this decides which entry is read. Fly.io appends two, the address it observed and then the app's own anycast address, so it needs `1`; a proxy that appends only its own observation needs `0`. Confirm it against a real request, because the wrong count records a plausible looking address belonging to the wrong machine. |

## Device endpoint

Prod only. Configures `NervesHubWeb.DeviceEndpoint`, and is only read when
`NERVES_HUB_APP` is `all` or `device`. This endpoint always serves HTTPS
directly — it terminates mutual TLS itself and cannot sit behind a proxy that
terminates TLS for it, because device certificates are the authentication
mechanism (see [Device authentication](device_authentication.md)). It can sit
behind one that passes the connection through, in which case `DEVICE_PROXY_PROTOCOL`
is how a device's own address survives the hop.

| Variable | Default | Description |
| --- | --- | --- |
| `DEVICE_HOST` | `WEB_HOST`, then `HOST` | Hostname devices connect to, e.g. `device.mynerveshub.com`. Boot raises if none of the three is set. |
| `DEVICE_PORT` | `443` | Port the device HTTPS listener binds to. |
| `DEVICE_SSL_KEY` | — | Base64-encoded private key. Written to `/app/tmp/ssl_key.crt` at boot. |
| `DEVICE_SSL_KEYFILE` | `/etc/ssl/$DEVICE_HOST-key.pem` | Path to the private key, used when `DEVICE_SSL_KEY` is unset. Boot raises if the file does not exist. |
| `DEVICE_SSL_CERT` | — | Base64-encoded certificate. Written to `/app/tmp/ssl_cert.crt` at boot. |
| `DEVICE_SSL_CERTFILE` | `/etc/ssl/$DEVICE_HOST.pem` | Path to the certificate, used when `DEVICE_SSL_CERT` is unset. Boot raises if the file does not exist. |
| `DEVICE_SSL_CACERTFILE` | the `castore` CA bundle | Path to a CA bundle. Boot raises if the file does not exist. |
| `DEVICE_ENABLE_TLS_13` | `false` | When false, the endpoint enforces TLS 1.2. Turn it on only if every device runs OTP >= 25.1 — older OTP 25 releases can break negotiating 1.3 or 1.2. See [erlang/otp#6492](https://github.com/erlang/otp/issues/6492#issuecomment-1323874205). |
| `DEVICE_SHARED_SECRETS_ENABLED` | `false` | Allow devices to authenticate with a shared secret instead of a certificate. Easier onboarding, weaker authentication. |
| `DEVICE_HOST_STATUS_PORT` | `4040` | Port for the plain-HTTP health check endpoint. Only started when `NERVES_HUB_APP=device`. |
| `DEVICES_WEBSOCKET_HOST` | `DEVICE_HOST`, then `WEB_HOST`, then `HOST` | Host shown in the UI's device connection instructions. Read in every environment. |
| `DEVICE_ENDPOINT_REDIRECT` | `https://docs.nerves-hub.org/` | Where a plain browser request to the device endpoint is redirected. |
| `DEVICE_CONNECT_RATE_LIMIT` | `100` | Maximum device connections accepted per second. Read in every environment. |
| `DEVICE_PROXY_PROTOCOL` | — | Set to `v2` when a load balancer passes TLS through to this endpoint and announces the device with a PROXY protocol v2 header, which is read before the TLS handshake. Only `v2` is supported; version 1 cannot be read without risking a read into the handshake that follows it, and any other value raises at boot. Turning it on is a flag day: a balancer sending the header to a listener that is not expecting it looks like a malformed ClientHello, and a listener expecting one that never arrives waits until it times out. On Fly.io keep it in `fly.toml` `[env]` beside the `proxy_proto` handler so each machine picks up the pair together — `fly secrets set` without `--stage` restarts the fleet before the handler exists. |

### Socket drainer

Read in every environment. On shutdown a device node disconnects its sockets in
batches so that reconnecting devices spread across the remaining nodes instead
of arriving all at once.

| Variable | Default | Description |
| --- | --- | --- |
| `DEVICE_SOCKET_DRAINER_BATCH_SIZE` | `1000` | Sockets closed per batch. |
| `DEVICE_SOCKET_DRAINER_BATCH_INTERVAL` | `4000` | Milliseconds between batches. |
| `DEVICE_SOCKET_DRAINER_SHUTDOWN` | `30000` | Milliseconds to allow for draining before shutdown continues regardless. |

## Database

Prod only, apart from the TLS settings, which are computed in every
environment.

| Variable | Default | Description |
| --- | --- | --- |
| `DATABASE_URL` | — (**required**) | Postgres connection URL. |
| `DATABASE_SSL` | `true` | Connect over TLS. Set to anything but `"true"` to disable. |
| `DATABASE_PEM` | — | Base64-encoded PEM bundle of CA certificates to verify the server against. Without it the system CA store is used. |
| `DATABASE_CERT_SELF_SIGNED` | `false` | Verify a self-signed server certificate against the first certificate in `DATABASE_PEM` rather than doing normal peer verification. Only meaningful with `DATABASE_PEM`. |
| `DATABASE_POOL_SIZE` | `20` | Connections per pool. |
| `DATABASE_POOL_COUNT` | `1` | Number of pools. |
| `DATABASE_INET6` | `false` | Connect over IPv6. |
| `DATABASE_AUTO_MIGRATOR` | `true` | Run pending Postgres migrations on boot. |

## Analytics (ClickHouse)

Prod only. Analytics — device connection history, metrics, the Insights pages
and the device message log — are enabled by setting `CLICKHOUSE_URL`. With it
unset the feature is off and none of the other variables here are read.

| Variable | Default | Description |
| --- | --- | --- |
| `CLICKHOUSE_URL` | — | ClickHouse connection URL. Setting it enables analytics. |
| `ANALYTICS_POOL_SIZE` | `10` | Connections per pool. |
| `ANALYTICS_POOL_COUNT` | `1` | Number of pools. |
| `ANALYTICS_AUTO_MIGRATOR` | `true` | Run pending ClickHouse migrations on boot. |
| `ANALYTICS_BUFFER_MAX_BATCH_SIZE` | `1000` | Rows buffered before a write is flushed. |
| `ANALYTICS_BUFFER_MAX_DELAY_MS` | `500` | Milliseconds before a partial batch is flushed anyway. |
| `ANALYTICS_BUFFER_MAX_SIZE` | `50000` | Buffer ceiling, for when ClickHouse is unreachable. The oldest rows are dropped once the buffer passes it. |
| `DEVICE_MESSAGES_MAX_PAYLOAD_BYTES` | `8192` | How much of a single device message body is stored. Longer bodies are truncated. |

## Firmware and archive uploads

`FIRMWARE_UPLOAD_BACKEND` is prod only; the size limits apply in every
environment.

| Variable | Default | Description |
| --- | --- | --- |
| `FIRMWARE_UPLOAD_BACKEND` | `local` | `local` or `S3`. Any other value raises at boot. |
| `FIRMWARE_UPLOAD_MAX_SIZE` | `200000000` | Maximum firmware upload size in bytes (200MB). |
| `ARCHIVE_UPLOAD_MAX_SIZE` | `200000000` | Maximum archive upload size in bytes (200MB). |

### Local backend

| Variable | Default | Description |
| --- | --- | --- |
| `FIRMWARE_UPLOAD_PATH` | — | Directory firmware and archives are written to. Must be on storage that persists across restarts, and shared between nodes if you run more than one. |

### S3 backend

| Variable | Default | Description |
| --- | --- | --- |
| `S3_BUCKET_NAME` | — (**required** for S3) | Bucket firmware and archives are stored in. |
| `S3_ACCESS_KEY_ID` | — | Access key. Leave both key variables unset to use the instance's ambient credentials (IAM role, environment, etc.). |
| `S3_SECRET_ACCESS_KEY` | — (**required** if `S3_ACCESS_KEY_ID` is set) | Secret key. |
| `S3_REGION` | ex_aws default | Bucket region. |
| `S3_HOST` | ex_aws default | Endpoint host, for S3-compatible services. |
| `S3_BUCKET_AS_HOST` | `false` | Generate presigned URLs with the bucket as the host, for providers that address buckets that way. |

## Email

Prod only. Without `SMTP_SERVER` the mailer is left unconfigured and no mail is
sent. The addresses and names below are read in every environment.

| Variable | Default | Description |
| --- | --- | --- |
| `SMTP_SERVER` | — | SMTP relay host. Setting it enables the SMTP adapter and makes the other `SMTP_*` variables required. |
| `SMTP_PORT` | — (**required** with `SMTP_SERVER`) | Relay port. |
| `SMTP_USERNAME` | — (**required** with `SMTP_SERVER`) | Relay username. |
| `SMTP_PASSWORD` | — (**required** with `SMTP_SERVER`) | Relay password. |
| `SMTP_SSL` | `false` | Use implicit TLS. STARTTLS is always attempted regardless, with peer verification against the system CA store. |
| `SMTP_TLS_VERSIONS` | — | Comma-separated TLS versions, e.g. `tlsv1.2,tlsv1.3`. Unset lets the TLS stack choose. |
| `FROM_EMAIL` | `no-reply@nerves-hub.org` | From address on outgoing mail. |
| `EMAIL_SENDER` | `NervesHub` | Display name on outgoing mail. |
| `SUPPORT_EMAIL_PLATFORM_NAME` | `NervesHub` | Product name used in email bodies. |
| `SUPPORT_EMAIL_ADDRESS` | — | Support address offered to recipients. |
| `SUPPORT_EMAIL_SIGNOFF` | — | Sign-off line at the end of email bodies. |

## Accounts and sessions

| Variable | Default | Description |
| --- | --- | --- |
| `OPEN_FOR_REGISTRATIONS` | `false` | Allow anyone to create an account. Prod only. |
| `GOOGLE_CLIENT_ID` | — | Setting it enables "Sign in with Google". |
| `GOOGLE_CLIENT_SECRET` | — | OAuth client secret. |
| `SESSION_COOKIE_DOMAIN` | — | Scopes the session cookie to a parent domain, e.g. `.example.com`, so a sibling subdomain can read it. Used for shared-session SSO between apps. |
| `LOGIN_RETURN_URLS_ALLOWED_LIST` | — | Comma-separated URLs that login is allowed to return to. Anything not listed is refused. |

## Device data retention and housekeeping

Read in every environment. Several of these bound the work done by an Oban cron
job in a single run — raise the limits if a table is growing faster than the
job can trim it.

| Variable | Default | Description |
| --- | --- | --- |
| `HEALTH_CHECK_DAYS_TO_RETAIN` | `7` | Days of device health and metric records kept. |
| `DEVICE_HEALTH_DELETE_LIMIT` | `100000` | Rows deleted per truncation run. |
| `DEVICE_CONNECTION_UPDATE_LIMIT` | `100000` | Stale connection rows updated per run. |
| `DEVICE_LAST_SEEN_UPDATE_INTERVAL_MINUTES` | `15` | How often a connected device's `last_seen_at` is written. Lower values mean fresher data and more writes. |
| `DEVICE_LAST_SEEN_UPDATE_INTERVAL_JITTER_SECONDS` | `300` | Random spread added to that interval so a fleet does not write in lockstep. |
| `TRUNCATE_AUDIT_LOGS_ENABLED` | `false` | Delete old audit log entries. Off means audit logs are kept forever. |
| `TRUNCATE_AUDIT_LOGS_DEFAULT_DAYS_KEPT` | `30` | Days of audit log kept, for organizations that have not set their own retention. |
| `CLEAN_UP_SOFT_DELETED_DEVICES` | `false` | Let the cron job hard-delete devices that have been soft deleted. |

## Device extensions

Read in every environment. Extensions are negotiated per device; these are the
instance-wide intervals.

| Variable | Default | Description |
| --- | --- | --- |
| `FEATURES_GEO_INTERVAL_MINUTES` | `0` | How often a device reports its location. `0` means once, on connection. |
| `FEATURES_HEALTH_INTERVAL_MINUTES` | `60` | How often a device reports health metrics. |
| `FEATURES_HEALTH_UI_POLLING_SECONDS` | `60` | How often the health pages refresh. |
| `EXTENSIONS_LOGGING_DAYS_TO_KEEP` | `3` | Days of device logs kept. |

## Firmware formats

Read in every environment. Both formats are experimental, and each also has to
be enabled per product once the instance allows it.

| Variable | Default | Description |
| --- | --- | --- |
| `ESP_IDF_FIRMWARE_ENABLED` | `false` | Accept ESP-IDF application images (`.bin`). See [ESP-IDF support](esp_idf_support.md). |
| `ATOMVM_FIRMWARE_ENABLED` | `false` | Accept AtomVM images. See [AtomVM support](atomvm_support.md). |

## Deployments

| Variable | Default | Description |
| --- | --- | --- |
| `DEFAULT_LIFO_DEPLOYMENT_QUEUE` | `false` | New deployment groups default to a last-in-first-out update queue, so the most recently connected devices are updated first. |

## Branding and UI

Read in every environment.

| Variable | Default | Description |
| --- | --- | --- |
| `WEB_TITLE_SUFFIX` | `NervesHub` | Suffix on browser page titles. |
| `LOGO_URL` | — | Logo used in the UI. |
| `LOGO_URL_LIGHT` | `LOGO_URL` | Logo for light mode. |
| `LOGO_URL_DARK` | `LOGO_URL` | Logo for dark mode. Set both light and dark to serve a different image per theme. |
| `MAPBOX_ACCESS_TOKEN` | — | Enables the map on the device page. Without it, location is shown as text. |
| `FEATUREBASE_APP_ID` | — | Enables the Featurebase feedback widget. |
| `FEATUREBASE_SIGNING_TOKEN` | — | Signing key used to identify the logged-in user to Featurebase. |

### Iroh endpoints

Read in every environment. The Iroh Endpoints page lets an organization manage
its own relays.

| Variable | Default | Description |
| --- | --- | --- |
| `ORG_IROH_ENDPOINTS_UI_ENABLED` | `false` | Show the Iroh Endpoints page. |
| `ORG_IROH_ENDPOINTS_INFO_URL` | — | Where this deployment sends people who want to know about its relays — a hosted offering's page, or an internal runbook. |
| `ORG_IROH_ENDPOINTS_INFO_LABEL` | host of the URL above | Link text for that URL. |

## Logging

`LOG_LEVEL` is read in every environment; the logfmt formatter is prod only.

| Variable | Default | Description |
| --- | --- | --- |
| `LOG_LEVEL` | Mix env default | Elixir logger level, e.g. `debug`, `info`, `warning`, `error`. |
| `LOG_INCLUDE_MFA` | `false` | Include the module, function and arity in log metadata. |
| `LOGGER_EXCLUSIONS` | — | Comma-separated telemetry events to stop logging, written dotted, e.g. `nerves_hub.devices.connect,nerves_hub.devices.disconnect`. Useful for quieting per-device connection churn on a large fleet. The full list of events is in [`NervesHub.Logger.attach/0`](../lib/nerves_hub/logger.ex). |

## Error reporting and tracing

Read in every environment.

| Variable | Default | Description |
| --- | --- | --- |
| `SENTRY_DSN_URL` | — | Sentry DSN. Without it, nothing is sent. |
| `SENTRY_ENABLE_LOGGING` | `false` | Forward logs to Sentry, not just exceptions. |
| `SENTRY_ENABLE_TRACING` | `false` | Send traces to Sentry via OpenTelemetry. |
| `SENTRY_TRACING_RATE` | `0.05` | Fraction of transactions sampled. Oban's own polling queries are sampled at 1% regardless. |
| `OTLP_ENDPOINT` | — | Send traces to an OTLP collector over HTTP instead. Only used when `SENTRY_ENABLE_TRACING` is off; with neither set, trace export is disabled entirely. |
| `OTLP_SAMPLER_RATIO` | — | Fraction of root traces sampled, as a float, e.g. `0.05`. Must contain a decimal point. |
| `OTLP_AUTH_HEADER` | — | Name of an auth header to send with exports, e.g. `authorization`. |
| `OTLP_AUTH_HEADER_VALUE` | — | Value for that header. |
| `STATSD_HOST` | — | Setting it enables StatsD metrics. |
| `STATSD_PORT` | `8125` | StatsD port. |
