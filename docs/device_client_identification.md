# Identifying the Device Client

NervesHub records which client library each device connects with, and which
version of it. Both are stored per connection, in the `lib` and `lib_version`
columns of `latest_device_connections` (Postgres) and of
`device_connection_history` (ClickHouse).

`device_api_version`, which devices send when they join, only covers ranges of
releases: `2.3.0` spans NervesHubLink 2.8.1 to 2.12.x. To know whether a device
has a particular fix or behaviour, such as following a websocket redirect
(NervesHubLink 2.10.0 and later), you need the library's own version.

## What a client sends

A client names itself in the `User-Agent` header of its websocket upgrade
request, as a product token:

```
User-Agent: <name>/<version>
```

These are the names NervesHub recognises:

| Client | Header | Recorded `lib` |
| --- | --- | --- |
| NervesHubLink | `NHL/2.13.0` | `nerves_hub_link` |
| nerves-hub-link-agent (Rust, Linux) | `nerves-hub-link-agent/0.1.0` | `nerves_hub_link_agent` |
| nerves-hub-link-esp32 (Rust, ESP-IDF) | `nerves-hub-link-esp32/0.1.0` | `nerves_hub_link_esp32` |
| nerves_hub_link_atomvm_esp32 (AtomVM) | `nerves_hub_link_atomvm_esp32/0.2.0` | `nerves_hub_link_atomvm_esp32` |

NervesHubLink already sends `NHL/<version>` when it downloads firmware, so the
websocket uses the same token.

The rules, all in `NervesHub.Devices.ClientLibrary`:

- **The first recognised token wins.** A client can add more tokens after its
  own, such as its HTTP library: `NHL/2.13.0 Mint/1.7.1`.
- **Tokens inside a parenthesised comment are ignored.** A comment describes
  something else, such as the platform: `nerves-hub-link-esp32/0.1.0 (esp-idf 5.2.3)`.
- **Names are matched exactly**, case included.
- **The version must be SemVer**, 64 characters at most, with no leading `v`.
  If the name is recognised but the version isn't valid, NervesHub records the
  library and leaves the version unknown.
- **Anything else is unknown.** A missing header, an unrecognised name, or an
  HTTP library's default (`ESP32 Websocket Client`) leaves both columns `NULL`
  in Postgres and empty in ClickHouse.

Every connection is recorded fresh. If a device reconnects without the header,
its library goes back to unknown; NervesHub doesn't keep the value from the
previous connection.

## Why the User-Agent

NervesHub reads the header from the HTTP upgrade, before the device has
authenticated, been redirected, or joined a channel. That means the first
history row for a connection already has the library. It also means anything
decided at the upgrade can take the client into account, such as whether to
redirect a device to another host.

A join param wouldn't be available until after all of that. `User-Agent` is
also the header HTTP defines for this purpose, and every websocket client
these devices use can set it.

## Setting it with ESP-IDF

`esp_websocket_client` and `esp_transport_ws` write their own
`User-Agent: ESP32 Websocket Client` line before any extra headers you give
them. NervesHub reads the first `User-Agent` header, so putting yours in the
extra headers block does nothing. Set the client's `user_agent` field instead:
`esp_websocket_client_config_t.user_agent`, or
`esp_transport_ws_config_t.user_agent` when you supply the transport yourself.

## Adding a client

Add its product token and the name to record to `@libraries` in
`NervesHub.Devices.ClientLibrary`, and add a row to the table above. A client
NervesHub doesn't know about connects as usual, with its library recorded as
unknown.

## Nodes that hold device sockets elsewhere

The header is parsed on the node that records the connection, not the node
holding the socket. A node that holds device sockets and reaches the platform
through `NervesHub.DeviceLink.Dispatcher.Remote` therefore needs two things:

- `:user_agent` in its device socket's `connect_info`
- to pass the header on, through `NervesHub.DeviceLink.Client.connect/3`

`NervesHub.DeviceLink.connect/3` only exists from this release, so the platform
has to be upgraded before any node starts calling it. A node still calling
`connect/2` keeps working; its devices are recorded with an unknown library.
