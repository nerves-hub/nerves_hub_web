# Changelog

## Unreleased

### Added

- Add a way to extend DeviceChannel functionality via Extensions (#1479)
- Hide disabled extensions in the UI (#1654)
- Check device api version before requesting extensions (#1668)

### Changed

- Replace Scrivener with Flop for pagination (#1656)
- Improve pager (#1664)

### Fixed

- Fix device pager not paging back to page 1 (#1663)

### Dependencies

- **bandit**: 1.6.0 -> 1.8.0
- **bcrypt_elixir**: 3.2.0 -> 3.3.2
- **castore**: 1.0.8 -> 1.0.10
- **certifi**: removed
- **ch**: 0.5.6
- **circular_buffer**: 0.4.1 -> 1.0.0
- **comeonin**: 5.5.0 -> 5.5.1
- **confuse**: 0.2.1
- **crontab**: 1.1.14 -> 1.2.0
- **dialyxir**: 1.4.3 -> 1.4.4
- **ecto**: 3.12.3 -> 3.12.4
- **ecto_psql_extras**: 0.8.1 -> 0.8.2
- **ecto_sql**: 3.12.0 -> 3.12.1
- **ex_aws**: 2.5.5 -> 2.5.7
- **ex_aws_s3**: 2.5.3 -> 2.5.5
- **expo**: 0.5.2 -> 1.1.0
- **floki**: 0.36.2 -> 0.36.3
- **gettext**: 0.24.0 -> 0.26.2
- **phoenix_ecto**: 4.6.2 -> 4.6.3
- **postgrex**: 0.19.2 -> 0.19.3
- **scrivener_ecto**: 3.0.0 -> 3.0.1
- **sentry**: 10.7.1 -> 10.8.0
- **slipstream**: 1.1.1 -> 1.1.2
- **swoosh**: 1.17.1 -> 1.17.2
- **telemetry_metrics**: 0.6.2 -> 1.0.0
- **telemetry_metrics_statsd**: 0.7.0 -> 0.7.1
- **tzdata**: 1.0.0 -> 1.1.0
- **x509**: 0.8.9 -> 0.8.10

## v2.1.0

### Added

- Add the oban integration to Sentry (#1543)
- Add container version tagging (#1549)
- Add device count and estimated device count for Deployment views (#1517)
- Use Chart.js for metrics (#1523)
- Add task for generating randomized device metrics (#1564)
- Add support for a release id for Sentry (#1568)
- Add option for showing updated devices on the map (#1592)
- Clear inflight updates for unhealthy devices (#1620)
- Show helpful message when uploading duplicate firmware (#1627)
- Add support for filtering devices on alarms (#1628)
- Have the calculator use Oban (#1639)
- Save device connection data over time (#1572)
- Add support for OpenTelemetry tracing (#1612)
- Show current alarms on device page (#1648)
- World Map clustering (#1619)

## Changed

- Device channel cleanups (#1546)
- Increase the Repo queue_target (#1545)
- Fix dialyzer warning about use of map where each would do (#1550)
- Use the Endpoint from the socket (#1558)
- Sentry integration tweaks (#1560)
- Remove the NodeReporter metrics logger (#1563)
- Only render connection tooltip when timestamp is present (#1565)
- Logger improvements (foundations) (#1556)
- Allow errors and warnings in test env (#1561)
- Separate logging from metrics (#1571)
- Allow the socket drainer to be configured at runtime (#1577)
- Use the endpoint from the socket (#1579)
- Reintroduce missing custom metrics and metadata to device page (#1578)
- Add y-scale start number as chart parameter (#1580)
- Metrics charts improvements (#1581)
- Only broadcast on terminate/2 if the channel is joined (#1586)
- Display selected option when moving device(s) to other product (#1591)
- Add firmware delta generation back in (#1582)
- Order platform dropdown + add unknown platform as selection (#1599)
- Group by deployment id when counting devices for deployments (#1600)
- Disable console button when device console is not available (#1605)
- Batch insert device metrics (#1613)
- Optimize the queries needed for Accounts.list_org_keys (#1614)
- Increase the Orchestrator timer, and add a jitter (#1615)
- Remove an extra Deployment preload during after_join (#1618)
- Allow publishing docker images from PR (#1626)
- Use PRs HEAD sha for tagging images (#1637)
- Use PR number when looking for publish commit message (#1638)

### Fixed

- Some minor dialyzer fixes (#1553)
- Update mix.exs Elixir version to match .tool-versions (#1621)
- Use the correct endpoint for pubsub broadcasts (#1634)
- Fix an unreachable with/else code path (#1642)
- Use the full module reference for some @specs (#1645)
- Change health section to not show boxes for non-reported default values (#1651)

### Dependencies
- **castore**: 1.0.8 -> 1.0.10
- **ex_aws_s3**: 2.5.3 -> 2.5.5
- **dialyxir**: 1.4.3 -> 1.4.5
- **bcrypt_elixir**: 3.1.0 -> 3.2.0
- **comeonin**: 5.4.0 -> 5.5.0
- **swoosh**: 1.17.1 -> 1.17.3
- **slipstream**: 1.1.1 -> 1.1.2
- **telemetry_metrics_statsd**: 0.7.0 -> 0.7.1
- **ecto**: 3.12.3 -> 3.12.4
- **ecto_sql**: 3.12.0 -> 3.12.1
- **telemetry_metrics**: 0.6.2 -> 1.0.0
- **ecto_psql_extras**: 0.8.1 -> 0.8.2
- **ex_aws**: 2.5.5 -> 2.5.7
- **x509**: 0.8.9 -> 0.8.10
- **postgrex**: 0.19.1 -> 0.19.3
- **floki**: 0.36.2 -> 0.36.3
- **crontab**: 1.1.13 -> 1.1.14
- **sentry**: 10.7.1 -> 10.8.0
- **phoenix_ecto**: 4.6.2 -> 4.6.3
- **gettext**: 0.24.0 -> 0.26.2
- **phoenix_live_dashboard**: 0.8.4 -> 0.8.5
- **bandit**: 1.5.7 -> 1.6.0
- **opentelemetry_bandit**: 0.2.0-rc.1 -> 0.2.0
- **opentelemetry_phoenix**: 2.0.0-rc.1 -> 2.0.0
- **open_telemetry_decorator**: 1.5.7 -> 1.5.8

From `assets/`:
- **webpack**: 5.45.1 -> 5.95.0
- **braces**: 3.0.2 -> 3.0.3

## v2.0.0

Trying to create a Changelog from the previous tagged version `v1.3.0` from
January 2023 is frankly a bit much.

The fundamentals:

- Performant at scale: It is used in production with hundreds of thousands of connected devices. It works well.
- Remove AWS: It is now easy to run and set up on any hosting platform

There is also a lot more. The [initial announcement of 2.0](https://elixirforum.com/t/introducing-nerveshub-2-0/55531/5)
has the basic idea. The only idea that isn't currently actively pursued or
already delivered is MQTT and that is bound to pop up again in the future.

A lot of this work should be credited to Eric Oestrich and he gave an update
on it at [the Nerves Meetup](https://www.youtube.com/watch?v=vSYbSTXL26I).

Jon Carstens covered some of the work during
[his NervesConf talk](https://www.youtube.com/watch?v=lHcC9gwk_rg) as a well.

After the 2.x changes were available Josh Kalderimis joined in and started
looking at ease of use which led to a lot of various improvements but the
biggest one is the alternative device authentication method: Shared Secret

Since then we have contributions from 19 people where Eric Oestrich dominates
the stats. Followed by Josh Kalderimis. Then Jon Carstens.

There are a lot of things planned. SmartRent, NervesCloud and other users of
the project are in active collaboration on improving the feature set, the
performance and the user experience. We want this to be not just a great tool
for developers that choose Nerves but a surprising delight and joy to use.

### Migration

You should be able to migrate using the Ecto migrations. Nothing should be
break if you migrate a 1.x install to the 2.x releases. We still recommend
that you set aside time for dealing with anything unusual that might come up.

You may also need some time to deprovision the AWS resources you no longer
need.
