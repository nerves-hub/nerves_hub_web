# AtomVM Support (experimental)

NervesHub can ingest AtomVM packbeam archives (`.avm`) alongside fwup archives
(`.fw`) and ESP-IDF application images (`.bin`). Support is experimental and
covers the server side only — see [Limitations](#limitations).

A packbeam is not a system image. Where an ESP-IDF `.bin` replaces everything
running on the device, a packbeam replaces only the application; the VM
underneath it is updated separately, if at all.

## Enabling it

Support is off by default, and is turned on in two places: once for the
instance, and once for each product that should accept the format.

### 1. The instance

Set `ATOMVM_FIRMWARE_ENABLED=true`. Without it, no `.avm` is recognised and no
product can opt in.

Off by default. Accepting a firmware format is a decision about what an
instance will take and store, not something a deploy should acquire by
upgrading, and an unsigned packbeam is accepted where an unsigned fwup archive
would not be. See [Firmware signing](#firmware-signing).

### 2. The product

Under **Product → Settings → Firmware**:

| Setting | Column | Default |
| --- | --- | --- |
| Accept AtomVM packbeam archives | `products.allowed_update_tools` | `["fwup"]` |

A product accepts only the formats listed in `allowed_update_tools`; fwup is
always among them. Uploading an `.avm` to a product that has not opted in is
rejected with a message naming the product.

Each format is toggled on its own. Turning one off leaves the others as they
were.

### Over the API

`allowed_update_tools` is on the product resource, and is settable with `PUT` or
`PATCH` (org role `manage`):

```bash
curl -X PATCH \
  -H "Authorization: token $NH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allowed_update_tools": ["fwup", "atomvm"]}' \
  https://<host>/api/orgs/<org>/products/<product>
```

Listing a tool the instance has not enabled returns a 422.

## Uploading

Upload a packbeam through the web UI or the API exactly as you would an fwup
archive. NervesHub identifies the format by inspecting the file rather than by
its extension: a packbeam opens with 24 bytes that double as a shebang, so a
file marked executable runs under AtomVM.

```
#!/usr/bin/env AtomVM\n\0\0
```

### Where the metadata comes from

A packbeam carries OTP application metadata as an entry named
`<app>/priv/application.bin`, holding a serialised `{application, Name, Props}`.
NervesHub reads it from there:

| Field | Source |
| --- | --- |
| `product` | the application name |
| `version` | `vsn` |
| `description` | `description` |
| `uuid` | SHA-256 of the archive, first 16 bytes |
| `platform` | always `atomvm` |
| `architecture` | always `beam` |

Nothing has to be added to a build beyond an application `vsn` that NervesHub
can read as a version.

`platform` and `architecture` describe the runtime rather than the silicon,
because a packbeam is portable bytecode and carries no chip or board identifier
anywhere. An archive that calls `esp:` NIFs is of course not portable in
practice; that distinction belongs to the product, which is already the level at
which a device family is modelled.

The UUID is derived from the archive's own bytes, so two uploads of identical
bytes are one firmware and any change produces a new one.

### Which application, when there are several

A packbeam built from a project with dependencies contains one
`application.bin` per application, and nothing in the file marks which is the
root — `atomvm_packbeam` has to be told, through its `application_module`
option. NervesHub takes the first, which is the project's own: the rebar3 plugin
builds its file list as

```erlang
reorder_beamfiles(BeamFiles) ++ AppFileBinFiles ++ BootFiles ++ PrivFilesRelative ++ AvmFiles
```

with the dependency archives last, and `packbeam_api:create/3` writes entries in
list order.

An archive assembled by hand in some other order would be read wrongly, and
would show up as firmware filed under a dependency's name.

### Versions must be SemVer

An OTP application `vsn` is free form and the compiler accepts anything, while
NervesHub requires strict SemVer. A leading `v` and a two part version are
accepted:

| `vsn` | Recorded as |
| --- | --- |
| `1.2.3` | `1.2.3` |
| `v1.2.3` | `1.2.3` |
| `1.2` | `1.2.0` |
| `1.2.3-rc.1` | `1.2.3-rc.1` |
| `git`, `1`, `1.2.3.4` | rejected |

An unreadable version is refused at upload rather than coerced into one that
would sort wrongly.

## Firmware signing

The packbeam format has no signature of its own: `atomvm_packbeam` writes none
and `avmpack_is_valid` compares the 24 byte magic and nothing else. NervesHub
adds one as a convention, in the shape fwup uses, where the signature travels
inside the archive as a sibling of what it signs.

```
magic
entry, entry, ...                 the archive as built
nerves_hub/signature   (data)     appended
terminator
```

The signed range is every byte before the signature entry begins. That is the
one rule such a scheme has to get right: the signed bytes must exclude the
signature itself, or it cannot be checked without already knowing what it was.
Because the signature is appended, nothing before it moves, so both ends
compute the same range without agreeing on anything else.

A signed archive still boots on a stock AtomVM. The entry is a data file, the
same class as `priv/application.bin`, which the VM skips when it looks for
code. Signing can only add a check, never take a device away.

### The key is your fwup key

An fwup private key is a 32 byte Ed25519 seed followed by its public key, and
that trailing half is byte for byte the `.pub` file NervesHub already stores as
an organization key. So an organization signs AtomVM firmware with the key it
already uses for fwup, and there is no new key management.

### Signing an archive

The `nh-avm` tool ships with
[nerves_hub_link_atomvm_esp32](https://github.com/nerves-hub/nerves_hub_link_atomvm_esp32):

```bash
nh-avm sign --key fwup-key.priv --in app.avm --out app-signed.avm
nh-avm verify --key fwup-key.pub --in app-signed.avm
```

`nh-avm keygen` writes the same file format for anyone not already using fwup,
and `fwup -g` produces files it accepts.

Signing changes the archive's bytes, so a signed archive has a different UUID
than the unsigned one. That is correct: it is a different artifact, and the same
is true of a signed fwup archive.

### What NervesHub does with it

An archive carrying a signature is verified against the organization's Ed25519
keys, and one that does not verify is refused whatever the product allows.

An archive carrying no signature is accepted and recorded with no key. Nothing
in the wider AtomVM toolchain signs by default, so refusing unsigned archives
would refuse everything built by anything but this tooling. Requiring signatures
is a per-product decision to add later, in the shape
`allow_unsigned_esp_idf_firmware` already has.

Namespacing and versioning are deliberate. AtomVM may define its own signing
one day: the entry is named under `nerves_hub/` so it cannot collide with
whatever that turns out to be, and the payload leads with a magic and a version
(`NH1`, version 1) so a second scheme is additive rather than a breaking change.

## Limitations

### Delta updates

Not supported, and none are generated. There is no equivalent of ESP-IDF's
`esp_delta_ota` component for AtomVM, so nothing on a device could apply a
patch. Generating one anyway would cost worker time and object storage and
report success in the UI for something unusable.

### The device side

This is the server half. NervesHub will accept, store and offer a packbeam, but
the agent that downloads one, writes it to an inactive partition and reboots
into it is a separate piece of work.

### VM and bootloader updates

Out of scope. A packbeam update replaces the application, not the VM it runs on
and not the bootloader. Updating AtomVM itself is a different artifact through a
different path.

## The device protocol

A device tells NervesHub which format it speaks by sending `update_tool` in its
join params:

```json
{ "update_tool": "atomvm" }
```

Without it, NervesHub identifies the format from the keys present.

### Reporting firmware metadata on join

| Param | Source on the device |
| --- | --- |
| `atomvm_app_name` | the application name from the booted packbeam |
| `atomvm_app_version` | its `vsn` |
| `atomvm_avm_sha256` | SHA-256 of the packbeam, hex encoded |
| `atomvm_version` | `erlang:system_info(atomvm_version)` |

The device sends a hash rather than a UUID. The mapping from one to the other is
NervesHub's convention, and keeping it in one place stops a device agent from
having to know it, or from getting it subtly wrong.

`atomvm_version` is the VM's own version, which no archive can know and which is
updated on a separate schedule from the application. It is recorded alongside
the firmware metadata as `AtomVM <version>`.

A device that does not hash its partition simply reports no UUID. That costs it
the database fallback NervesHub uses when the rest of a device's metadata is
incomplete, so it is worth sending.
