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

### Listed clients

These clients are recorded under a fixed name:

| Client | Header | Recorded `lib` |
| --- | --- | --- |
| NervesHubLink | `NHL/2.13.0` or `nerves_hub_link/2.13.0` | `nerves_hub_link` |
| nerves-hub-link-agent (Rust, Linux) | `nerves-hub-link-agent/0.1.0` | `nerves_hub_link_agent` |
| nerves-hub-link-esp32 (Rust, ESP-IDF) | `nerves-hub-link-esp32/0.1.0` | `nerves_hub_link_esp32` |
| nerves_hub_link_atomvm_esp32 (AtomVM) | `nerves_hub_link_atomvm_esp32/0.2.0` | `nerves_hub_link_atomvm_esp32` |

NervesHubLink already sends `NHL/<version>` when it downloads firmware, so it
can use the same token on the websocket. Both of its tokens are recorded the
same way.

### Custom clients

A client that isn't listed opts in by putting `custom:` in front of its name:

```
User-Agent: custom:acme-link/1.4.0
```

It's recorded under that name, prefix included: `lib` is `custom:acme-link`
and `lib_version` is `1.4.0`. Integrations written outside this project show
up without any change to NervesHub. The prefix keeps what a client says about
itself apart from the listed names, so `custom:nerves_hub_link` is never
counted as `nerves_hub_link`.

The name after the prefix can be at most 64 letters, digits, `.`, `_` and `-`,
starting with a letter or digit. That keeps the ClickHouse `LowCardinality`
columns to something like a list of clients.

An unlisted token without the prefix is skipped. That keeps out the defaults
HTTP libraries send when the client sets no `User-Agent`. Mint's matters most:
NervesHubLink connects with Mint, so a NervesHubLink that doesn't send its own
token sends `mint/<version>`. That's recorded as unknown, not as a library
called `mint`.

RFC 9110 doesn't allow `:` in a product token, but a header value can contain
it, and NervesHub's own tests send it through Mint unchanged.

### How the header is read

The rules, all in `NervesHub.Devices.ClientLibrary`:

- **The first token that names a client wins**, listed or custom, so a client
  puts its own token first. It can add more after it, such as its HTTP library:
  `NHL/2.13.0 Mint/1.7.1`. Tokens that name no client are skipped, so
  `mint/1.7.1 custom:acme-link/1.4.0` is still recorded as `custom:acme-link`.
- **Tokens inside a parenthesised comment are ignored.** A comment describes
  something else, such as the platform: `nerves-hub-link-esp32/0.1.0 (esp-idf 5.2.3)`.
- **Names and the prefix are matched exactly**, case included. `nhl/2.13.0`
  and `Custom:acme-link/1.4.0` name no client.
- **The version must be SemVer**, 64 characters at most, with no leading `v`.
  If it isn't, NervesHub records the library and leaves the version unknown.
- **Anything else is unknown.** A missing header, or one that names no client,
  leaves both columns `NULL` in Postgres and empty in ClickHouse.

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

## Listing a client

A new client doesn't need a change in NervesHub: it can send a `custom:`
token. Listing it lets it drop the prefix. Add its token and the name to record
to `@libraries` in `NervesHub.Devices.ClientLibrary`, and add a row to the
table above.

Listing a client that has been sending `custom:`, or changing a listed client's
recorded name, splits its history in two, because rows already written keep
the old name.

## Nodes that hold device sockets elsewhere

The header is parsed on the node that records the connection, not on the node
holding the socket, so changing the rules or the list needs no change there. A
node that holds device sockets and reaches the platform through
`NervesHub.DeviceLink.Dispatcher.Remote` only has to pass the header on, which
takes two things:

- `:user_agent` in its device socket's `connect_info`
- to pass the header on, through `NervesHub.DeviceLink.Client.connect/3`

`NervesHub.DeviceLink.connect/3` only exists from this release, so the platform
has to be upgraded before any node starts calling it. A node still calling
`connect/2` keeps working; its devices are recorded with an unknown library.
