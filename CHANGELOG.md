# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

See the [NervesHub documentation] for more information

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
