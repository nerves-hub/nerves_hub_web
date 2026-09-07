# RAUC Support (experimental)

NervesHub can ingest RAUC bundles (`.raucb`) alongside fwup archives (`.fw`),
ESP-IDF application images (`.bin`) and AtomVM packbeam archives (`.avm`).
Support is experimental and covers the server side only — see
[Limitations](#limitations).

RAUC is the update mechanism most Yocto and Buildroot systems reach for. Where a
Nerves device runs fwup, a Yocto device typically runs `rauc install`, and the
bundle it installs is a SquashFS image with a CMS signature appended.

## Enabling it

Support is off by default, and is turned on in two places: once for the
instance, and once for each product that should accept the format.

### 1. The instance

Set `RAUC_FIRMWARE_ENABLED=true`. Without it, no `.raucb` is recognised and no
product can opt in.

Off by default. Accepting a firmware format is a decision about what an instance
will take and store, not something a deploy should acquire by upgrading.

### 2. The product

Under **Product → Settings → Firmware**:

| Setting | Column | Default |
| --- | --- | --- |
| Accept RAUC bundles | `products.allowed_update_tools` | `["fwup"]` |

A product accepts only the formats listed in `allowed_update_tools`; fwup is
always among them. Uploading a `.raucb` to a product that has not opted in is
rejected with a message naming the product.

There is no "allow unsigned RAUC bundles" setting, unlike ESP-IDF and AtomVM.
RAUC will not build an unsigned bundle, so there is no such thing to allow.

### Over the API

The setting is on the product resource, and is settable with `PUT` or `PATCH`
(org role `manage`):

```bash
curl -X PATCH \
  -H "Authorization: token $NH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allowed_update_tools": ["fwup", "rauc"]}' \
  https://<host>/api/orgs/<org>/products/<product>
```

Listing a tool the instance has not enabled returns a 422.

## Requirements

### RAUC 1.9 or newer, at both ends

Two unrelated requirements land on the same version.

**Building.** `[meta.<label>]` manifest sections arrived in 1.9. Older versions
do not reject them — they *drop* them while rewriting the manifest into the
signature. A bundle built by RAUC 1.8 from a manifest containing
`architecture=aarch64` arrives without it, so the field is in the file you wrote
and not in the bundle you uploaded. NervesHub reports that case distinctly, as
"no `[meta.nerveshub]` section", rather than telling you to add a field that is
already there.

**Running.** `bundle.hash` — the field a device reads back to say which firmware
it is running — was added to slot status in 1.9. A 1.8 device installs and
reboots perfectly well, and then cannot answer the one question NervesHub asks
it.

### openssl on the server

NervesHub shells out to `openssl` to verify a bundle's CMS signature and read
the manifest out of it. This is a runtime dependency nothing else in NervesHub
has; the official container image installs it. If it is missing, uploads fail
with a message saying so rather than crashing.

### A note for developers

`.raucb` is registered as a MIME type in `config/config.exs`, because
`allow_upload` refuses any extension it cannot resolve to a known type. That
config is read at **compile time** by the `mime` library, so a working tree with
a stale `_build/mime` raises when the firmware page mounts — which takes out the
firmware index for every product, not only RAUC uploads. If you see that after
pulling this branch:

```bash
mix deps.compile mime --force
```

A fresh build is unaffected, so this is a local-development hazard rather than a
deployment one.

`rauc` itself is **not** required on the server. Everything NervesHub needs is
reachable from the bundle's footer, and `rauc` would pull in glib, dbus and
libcurl for a server that never installs a bundle — only reads one.

## Uploading

Upload a bundle through the web UI or the API exactly as you would an fwup
archive. NervesHub identifies the format by inspecting the file rather than by
its extension, then checks it against the product's `allowed_update_tools`.

### Verity bundles only

NervesHub reads bundles in the **verity** format and refuses **plain** ones with
a message saying so.

In a verity bundle the manifest lives *inside* the CMS signature, which is what
makes a single `openssl cms -verify` both check the signature and hand back the
manifest. In a plain bundle the signature is detached and the manifest is a file
inside the SquashFS, which would mean unpacking a filesystem to read four lines
of INI.

This is not much of a restriction. Verity is the format RAUC recommends, and it
is required for the HTTP streaming install that is the main reason to want RAUC
here at all. Set it in your manifest:

```ini
[bundle]
format=verity
```

### Where the metadata comes from

A RAUC manifest carries `compatible` and `version` and nothing else NervesHub
requires, so the rest comes from a `[meta.nerveshub]` section:

```ini
[update]
compatible=acme-gateway
version=1.4.2
description=nightly

[bundle]
format=verity

[meta.nerveshub]
product=Gateway
architecture=aarch64
```

| NervesHub field | Source |
| --- | --- |
| Product | `[meta.nerveshub] product`, falling back to `[update] compatible` |
| Version | `[update] version` |
| Architecture | `[meta.nerveshub] architecture` — **required** |
| Platform | `[meta.nerveshub] platform`, falling back to `[update] compatible` |
| UUID | first 128 bits of the SHA-256 over the embedded manifest |
| Description | `[update] description` |
| VCS identifier | `[update] build` |

`compatible` stands in for `platform` and `product` because it is the closest
thing RAUC has to either. `architecture` has no sensible default and is
required: NervesHub matches deployments on it, and a wrong guess would send an
arm64 bundle to an amd64 device.

The product name must match your NervesHub product, the same rule fwup uploads
follow.

### The UUID

RAUC has no notion of a firmware UUID, so NervesHub derives one from the SHA-256
over the manifest *as embedded in the signature* — the digest RAUC itself
computes and reports as `hash` in `rauc info --output-format=json`. What is
stored is the first 128 bits of it, formatted as a UUID, which is the same
truncation RAUC applies when it renders `bundle.hash`.

That identity is what makes the UUID useful rather than merely unique. RAUC
records the installed bundle's hash against the slot it went into, and that
survives reboots, so a device can read back what it is running with
`rauc status` and arrive at the same UUID NervesHub recorded at upload —
without NervesHub having told it.

It is stable for identical input, so a reproducible build produces the same
UUID, and it changes whenever anything in the manifest does, including the
checksum of every image in the bundle.

Note that `rauc` rewrites the manifest on the way into the signature, adding the
verity root hash and salt. The UUID is derived from what comes *out*, not from
the manifest you handed to `rauc bundle`.

## Firmware signing

RAUC signs with CMS against an X.509 keyring, so an organization's RAUC key is a
**certificate** rather than a bare public key. Register the signing certificate
against the organization, choosing the **X.509 certificate** scheme.

```bash
openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
  -keyout signing-key.pem -out signing-cert.pem -subj "/CN=acme-signing"

rauc bundle --cert signing-cert.pem --key signing-key.pem input-dir/ bundle.raucb
```

Register `signing-cert.pem`. A bundle must verify against a certificate the
organization holds, or the upload is rejected.

### Trust is scoped to the organization's keyring

NervesHub verifies a bundle against the organization's registered certificates
and **nothing else**. The host's system CA bundle is not consulted, so a bundle
whose signer chains to a public CA does not verify against an organization that
never issued it.

This matters if you sign with a leaf issued by your own CA rather than with a
self-signed certificate: register **the certificate that anchors the chain** —
the CA — not only the leaf. Registering the leaf works too, but then rotating
the leaf means registering the new one.

Only certificates are RAUC trust anchors. An organization may also hold fwup
Ed25519 keys and ESP-IDF Secure Boot RSA keys; those are ignored when verifying
a bundle, so an organization holding no certificate is told it has no key rather
than that the bundle is bad.

Signing does not affect the device. RAUC enforces its own keyring on install, so
a bundle signed with a key the device does not trust will not install regardless
of what NervesHub concluded.

## Limitations

### Delta updates

None, and there should never be any. RAUC's saving already comes from the device
fetching only the blocks its target slot lacks, using HTTP range requests
against the whole bundle. Generating a patch would cost worker time and object
storage to produce something nothing would ever ask for. Deployment groups with
delta updates enabled still send complete bundles to RAUC devices.

### The device side

NervesHub can store and serve bundles, and the device protocol below is
implemented server-side. A client for non-Nerves Linux devices is in early
development at https://github.com/nerves-hub/nerves-hub-link-agent.

### Bootloader updates

What a bundle contains is between your manifest and your slot configuration.
NervesHub does not inspect the images inside the SquashFS payload.

## The device protocol

A non-Nerves agent has two things to get right.

### Reporting firmware metadata on join

A Nerves device reports `nerves_fw_*` keys. A RAUC device reports `rauc_*` keys,
read from `rauc status`:

```json
{
  "update_tool": "rauc",
  "device_api_version": "2.2.0",
  "rauc_uuid": "65547c89-8185-3d08-7e73-551be4c47401",
  "rauc_version": "1.4.2",
  "rauc_platform": "acme-gateway",
  "rauc_product": "acme-gateway",
  "rauc_architecture": null,
  "rauc_compatible": "acme-gateway",
  "rauc_tool_version": "1.13"
}
```

`rauc_uuid` is the device's own `bundle.hash` for the running slot, truncated
and formatted the same way NervesHub does it at upload — which is how the two
agree without NervesHub telling the device anything.

`rauc_architecture` is null on purpose: RAUC records no architecture against a
slot, so the device cannot know it. NervesHub fills it in from the firmware it
matches by UUID.

`rauc_platform` and `rauc_product` both fall back to `rauc_compatible` when
absent, matching how the bundle's metadata was read at upload.

`update_tool` is optional — NervesHub also recognises a device by the keys it
sends — but sending it explicitly is preferred.

### Reporting update progress

Send `update_progress` with a `value` percentage and an optional `stage`
(`downloading`, `updating`), the same as any other non-Nerves agent.
