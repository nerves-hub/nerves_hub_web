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

Off by default because nothing signs a packbeam today, so every archive an
instance accepts is unsigned. That is a decision about the instance's
trust model rather than something a deploy should acquire by upgrading. See
[Firmware signing](#firmware-signing).

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

None today. `atomvm_packbeam` writes no signature, `avmpack_is_valid` checks
the 24 byte magic and nothing else, and AtomVM has no verification step. Every
archive is therefore recorded as legitimately unsigned, with no `org_key_id`,
rather than failing verification — which is why the instance-wide flag is the
place the trust decision is made.

What is missing is a convention, not room in the file. fwup's approach carries
over directly: signing an fwup archive adds a `meta.conf.ed25519` entry *inside*
the zip, alongside the `meta.conf` it signs, and `meta.conf` covers the payload
by hash. The signature is a sibling of what it signs, never part of it.

A packbeam has the same shape available. A manifest entry listing the hash of
every other entry, plus a signature entry over that manifest, are both data
files the VM already ignores when loading. What matters is only that the signed
byte range excludes the signature itself, which this satisfies.

Defining that would change NervesHub and the device agent. It would not change
the packbeam format, and it needs no database change: a signed archive would
simply record an `org_key_id` the way an fwup archive does.

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
