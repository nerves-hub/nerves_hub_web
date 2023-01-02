# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

See the [NervesHub documentation] for more information

## [v1.3.0] - 2023-01-02

[v1.3.0]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.3.0

### Potentially Breaking Change

Versions were updated to Elixir 1.14.2 and OTP 25.2. Much testing has been done to
attempt to catch any potential SSL/TLS issues before release and the update should
be fairly safe, but it is worth keeping an eye on.

### Added

* Add `NervesHubWebCore.Workers.TruncateAuditLogs` for periodic cleaning of
  audit logs table (thanks @LostKobrakai)
* Firmware UUIDs hyperlink to the firmware#show page (thanks @TheCraftedGem)
* Add pretty 404 Not Found page (thanks @TheCraftedGem)
* Audit Log on device disconnect (thanks @TheCraftedGem)

### Fixed

* TLS 1.2 is forced for support with past OTP versions and to prevent
  devices using cryptochips from being able to connect
  * Note: `:sha` and `:sha224` signature algorithms were dropped as there is a potential
    bug negotiating them on a device with cryptochips if the server presents them as options.
    Since they are not typically used, it was decided to remove the support to fix the bug
    until more investigation can be done when reviewing OpenSSL 3.0
* [#871] Fix JITP>product relation to allow multiple profiles (thanks @jeanparpaillon)
* `DeviceLive.Index` now sorts and paginates via the database instead of loading
  all devices into memory. Fixes an issue where a production with thousands of devices
  may fail to load the index page (thanks @oestrich)
  * Moving to the DB level broke the ability to sort/query by `Connection Status`.
    This will be adjusted and fixed in a later release
* Fix incorrect query in `Fix Accounts.get_user_by_email_or_username/1` (Thanks @zolakeith!)
* Paginate audit logs instead of loading the complete feed (thanks @LostKobrakai)
* Sort devices `Last Communication` correctly when `nil`

### Updated

* Device imports now support certificates Base64 encoded as DER format
* Sort firmware dropdown options by version number (thanks @TheCraftedGem)

## [v1.2.0] - 2022-10-18

[v1.2.0]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.2.0

### Potentially Breaking Change

* Moved flag for enabling/disabling Delta updates to the `Deployment` instead of
  the `Product`. This allows for more granular control over which devices get
  Delta updates. This will require migrations to be run before use.

## [v1.1.0] - 2022-10-07

[v1.1.0]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.1.0

### Fixed

* Default to TLS 1.2 for all connections. This fixes issues if TLS 1.3 is
  used or attempted. See [NervesHubWeb: Potential SSL Issues](https://github.com/nerves-hub/nerves_hub_web#potential-ssl-issues)

## [v1.0.4] - 2022-10-07

[v1.0.4]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.0.4

### Fixed

* Fix return value passed to consume_upload_entry/3 (thanks @tonnenpinguin)

## [v1.0.3] - 2022-07-28

[v1.0.3]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.0.3

### Fixed

* [#844] Removed JoshJS to fix bug preventing some pages from loading (:heart: @pojiro)
* [#847] `settings/<org>/certificates` would crash if certificate had a JITP profile (:heart: @pojiro)

### Updated

* JavaScript library updates
  * `moment` 2.29.2 -> 2.29.4
  * `terser` 5.12.1 -> 5.14.2

## [v1.0.2] - 2022-07-01

[v1.0.2]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.0.2

### Fixed

* [#838] Unregistered, expired signer CAs in the device connection request
  would fail before the device certificate pin could be checked

## [v1.0.1] - 2022-06-28

[v1.0.1]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.0.1

### Fixed

* Fixed on/off toggling on deployment#show page (thanks @tonnenpinguin!)

## [v1.0.0] - 2022-06-10

[v1.0.0]: https://github.com/nerves-hub/nerves_hub_web/releases/tag/v1.0.0

The official start of NervesHub versioning. See the [NervesHub documentation]
for more information and [Custom Deployment](https://docs.nerves-hub.org/nerves-hub/custom-deployment)
guide for setting up your own instance.

[NervesHub documentation]: https://docs.nerves-hub.org
