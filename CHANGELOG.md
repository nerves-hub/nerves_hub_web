# Changelog

Format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

# [v2.2.0] - 2025-01-14

## Extensions

This release combines with [nerves_hub_link v2.6.0](https://github.com/nerves-hub/nerves_hub_link/releases/tag/v2.6.0) to bring the complete Extensions experience to NervesHub. An Extension is a non-critical but useful mechanism that needs to piggy-back on the device's connection to NervesHub. Rather than opening more connections or risking that the critical firmware delivery socket fails we have wrapped both ends of the socket in safeties.

Extensions are only enabled after the essential connection is confirmed and firmware delivery is possible. Each extension is also opt-in at the product level under product settings and possible to opt out at the device level under device settings. These changes can importantly be made at run-time in the UI. We want to ensure that if anything is wrong with an extension or it somehow disrupts critical operation it is trivial to disable immediately. This is to ensure that firmware updates and trouble-shooting come first.

The upshot of this is that we can build some very nice features without touching the core of what NervesHub must do. More on those below.

### Extension: Health

Health reporting lets your device send metrics, metadata and alarms to NervesHub giving you indicators about your device fleet's health. Health information is shown on the device details page when the extension is enabled and as information gets reported.

Default metrics, if supported by the hardware:

- CPU temperature
- CPU utilization
- Load averages (1, 5, 15 min respectively)
- Memory usage
- Disk usage

Adding custom metrics to the default report is a minimal addition in `config.exs` on `nerves_hub_link`:

```
config :nerves_hub_link,
  health: [
    # metrics are added with a key and MFA
    # the function should return a number (int or float is fine)
    metrics: %{
      "battery_percent_remaining" => {MyBattery, :percent_remains, []}
    }
  ]
```

There are many more features planned for metrics. Filtering, monitoring levels and various types of acting on metrics being out of bounds to provide a good idea about device health.

Alarms are a very nice way to find out if your devices is experiencing issues and uses the Erlang `:alarm_handler` functionality. The default alarm handler is not intended for real use and when it is used we won't report alarms because they don't behave very well. The alarm handler we know well and can recommend is [alarmist](https://hex.pm/packages/alarmist).

The device list can be filtered by devices with any alarms, specific alarms and your navigation bar within a product will indicate devices with alarms helping you quickly spot and find the list of devices with active alarms.

### Extension: Geo

Geo allows your device to report location information. By default it uses a Geo-IP mechanism through an API call to a web service. This gives a rough location. A device with location information can be shown on the Dashboard map which is enabled by setting `DASHBOARD_ENABLED=true`. If you configure a [Mapbox](https://www.mapbox.com/) API key via the environment variable `MAPBOX_ACCESS_TOKEN` it will fetch a local map for the device details page as well.

There are certainly more things we want to do in terms of filtering and useful maps with this geo-location information and this is the starting point.

Your device may well have a better way to get location data, whether LTE, GPS or manually entered coordinates you can modify the device's `config.exs` to include:

```
config :nerves_hub_link,
  geo: [
    # Implement your  `NervesHubLink.Extensions.Geo.Resolver`, just one function
    resolver: MyGPS.Resolver
  ]
```

## Deployment Recalculation Changes


## UI Rework


### Added

- Device Extensions
  - Add a way to extend DeviceChannel functionality via Extensions (#1479)
  - Hide disabled extensions in the UI (#1654)
  - Check device api version before requesting extensions (#1668)
  - Adjust minimum device_api_version for extensions (#1671)
  - Encapsulate health check requests into Extensions.Health (#1703)
  - Log unsupported API version when requesting device extensions (#1701)
- UI Refresh Foundation
  - Updated foundations for the UI refresh (#1665)
  - Support switching between the new and old UI (#1676)
  - Include New UI asset building in Dockerfile (#1685)
  - Initial version of org and product picker (#1673)
  - Fix slideover causing horizontal scroll (#1680)
- Bulk move devices to deployment (#1718)
- Check the DB during `/status/alive` calls (#1705)
- Add metrics filtering to devices query (#1598)
- Clean stale DeviceConnections (#1747)

### Changed

- Update Elixir and Erlang versions (#1693)
- Pagination tool replacement and fixes
  - Replace Scrivener with Flop (#1656)
  - Fix device pager not paging back to page 1 (#1663)
  - Improve pager (#1664)
  - Fix broken paginator (#1679)
- Deployments no longer recalculate their devices
  - Don't recalculate deployments for devices (#1652)
- File upload size limits
  - Allow for the firmware file size limit to be configurable (#1746)
  - Allow for custom Archive file size upload limits (#1754)
- Device UI clarification
  - Add script section to device UI (#1689)
  - Set deployment when viewing device (#1726)
  - Improve device buttons (#1731)
  - Create audit logs when setting deployment (#1737)
  - Relax restrictions when querying for eligible deployments (#1736)
  - A small device header simplification (#1755)
  - Remove Device From Deployment While Viewing It (#1712)
  - Refresh device-related assigns when receiving connection online message (#1738)
- Deployment UI clarification
  - A small Remove from Deployment UI tweak (#1729)
  - Move some Deployment info around (#1732)
  - Exclude deleted devices from Deployment device counts (#1735)
- Code-health improvements
  - The Credo experiment (#1740)
  - Fixes related to dialyzer warnings (#1715)
  - Fix a function signature call which recently changed (#1745)
  - Add a type to the AuditLog schema (#1730)
  - Correct the pattern matches when saving metrics
  - Address duplicated code and code path warnings
  - Deployments context specs (and some improvements) (#1733)
  - Some minor JS touchups (#1688)
  - ESLint upgrade and config (#1690)
- Improve metrics queries (#1655)
- Fetch the signing salt for the web socket connections from the config (#1721)
- Mix task best practises (#1756)

### Removed

- Replace `mox` with `mimic` (#1738)

### Fixed

- Make orchestrator and resolve_update respect deployment.is_active (#1743)
- Make sure the latest connection is loaded (#1719)
- Allow devices to have empty firmware when checking for deployments (#1748)
- Fix an incorrect call to retry device registration (#1687)
- Ignore empty metrics map in health report (#1694)

### Updated

- Elixir Dependencies

  - `bandit` 1.6.0 => 1.6.4
  - `castore` 1.0.10 => 1.0.11
  - `ecto` 3.12.4 => 3.12.5
  - `ecto_psql_extras` 0.8.2 => 0.8.3
  - `ex_aws` 2.5.7 => 2.5.8
  - `ex_aws_s3` 2.5.5 => 2.5.6
  - `floki` 0.36.3 => 0.37.0
  - `open_telemetry_decorator` 1.5.8 => 1.5.9
  - `phoenix` 1.7.14 => 1.7.18
  - `phoenix_live_dashboard` 0.8.5 => 0.8.6
  - `sentry` 10.8.0 => 10.8.1
  - `slipstream` 1.1.2 => 1.1.3
  - `sweet_xml` 0.7.4 => 0.7.5
  - `swoosh` 1.17.3 => 1.17.6

- JavaScript Dependencies
  - `json5` 1.0.1 => 1.0.2
  - `json-schema` 0.2.3 => 0.4.0
  - `jsprim` 1.4.1 => 1.4.2

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

### Changed

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
- Replace Scrivener with Flop for pagination (#1656)
- Improve pager (#1664)

### Fixed

- Some minor dialyzer fixes (#1553)
- Update mix.exs Elixir version to match .tool-versions (#1621)
- Use the correct endpoint for pubsub broadcasts (#1634)
- Fix an unreachable with/else code path (#1642)
- Use the full module reference for some @specs (#1645)
- Change health section to not show boxes for non-reported default values (#1651)
- Fix device pager not paging back to page 1 (#1663)

### Dependencies

- **bcrypt_elixir**: 3.1.0 -> 3.2.0
- **castore**: 1.0.8 -> 1.0.10
- **comeonin**: 5.4.0 -> 5.5.0
- **crontab**: 1.1.13 -> 1.1.14
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

Full Changelog - https://github.com/nerves-hub/nerves_hub_web/compare/v2.0.0...main

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
the project are in active collaboration on improving the featureset, the
performance and the user experience. We want this to be not just a great tool
for developers that choose Nerves but a surprising delight and joy to use.

### Migration

You should be able to migrate using the Ecto migrations. Nothing should be
break if you migrate a 1.x install to the 2.x releases. We still recommend
that you set aside time for dealing with anything unusual that might come up.

You may also need some time to deprovision the AWS resources you no longer
need.
