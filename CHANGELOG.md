# Changelog

## Unreleased

### Added
* Add the oban integration to Sentry (#1543)
* Add device count and estimated device count for Deployment views (#1517)
* Use Chart.js for metrics (#1523)
* Add task for generating randomized device metrics (#1564)

### Changed
* Device channel cleanups (#1546)
* Increase the Repo queue_target (#1545)
* Updates for releasing an official 2.0.0 version (#1548) (#1549)
* Remove EctoReporter and NodeReporter (#1554) (#1563)
* Fix typos (#1557)
* Sentry configuration and release id updates (#1560) (#1568)
* Logging changes (#1556) (#1561) (#1571)
  * Log from telemetry data
  * Move statsd metrics to a module
* Dependency updates
  * castore, 1.0.8 to 1.0.9
  * ex_aws_s3, 2.5.3 to 2.5.4

### Fixed
* Dialyzer fixes (#1553)
* Use the Endpoint from the socket (#1558)
* Update tzdata to fix an exception during boot (#1559)
* Only render connection tooltip when timestamp is present (#1565)

Full Changelog - https://github.com/nerves-hub/nerves_hub_web/compare/463ce1d...d8cbfc9

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
