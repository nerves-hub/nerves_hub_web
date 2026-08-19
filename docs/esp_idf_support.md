# ESP-IDF Support (experimental)

NervesHub can ingest ESP-IDF application images (`.bin`) alongside fwup archives
(`.fw`). This is the first non-fwup image format it handles, and it is
**incomplete** — read the [Not supported yet](#not-supported-yet) section before
relying on it.

## Enabling it

Support is off by default and has to be turned on in two places — once for the
instance, and once for each product that should accept the format.

### 1. The instance

Set `ESP_IDF_FIRMWARE_ENABLED=true`. Without it no product can opt in and no
`.bin` is recognised, whatever a product's settings say. Accepting a second
image format changes what an instance will ingest and serve, so it is a
deployment decision rather than something a version bump hands you.

### 2. The product

Under **Product → Settings → Firmware**:

| Setting | Column | Default |
| --- | --- | --- |
| Accept ESP-IDF application images | `products.allowed_update_tools` | `["fwup"]` |
| Allow unsigned ESP-IDF images | `products.allow_unsigned_esp_idf_firmware` | `false` |

A product accepts only the formats listed in `allowed_update_tools`; uploading a
`.bin` to a product that has not opted in is rejected with a message naming the
product, not silently ingested. fwup is always in the list.

The second setting is narrow on purpose: it excuses a *missing* signature block,
and nothing else. An image that carries a signature is always verified against
the organization's registered keys, and a bad signature is refused whether or
not the setting is on. See [Firmware signing](#firmware-signing).

Turning acceptance back off leaves the unsigned setting untouched, so a product
that is switched off and on again comes back configured as it was.

## What works

Upload an ESP-IDF application image through the web UI or the API exactly as you
would an fwup archive. NervesHub picks the handling tool by inspecting the file
itself rather than by extension, then checks that tool against the product's
`allowed_update_tools`.

### Where the metadata comes from

Nothing has to be added to your build. Every ESP-IDF image carries an
`esp_app_desc_t` at a fixed offset of `0x20`, and NervesHub reads it:

| NervesHub field | Source |
| --- | --- |
| Product | `esp_app_desc_t.project_name` (`PROJECT_NAME`) |
| Version | `esp_app_desc_t.version` (`PROJECT_VER`) |
| UUID | first 16 bytes of `esp_app_desc_t.app_elf_sha256` |
| Platform | `esp_image_header_t.chip_id`, e.g. `esp32s3` |
| Architecture | `esp_image_header_t.chip_id`, `xtensa` or `riscv` |
| Description | `esp_app_desc_t.idf_ver` |

`PROJECT_NAME` must match your NervesHub product name, the same rule fwup
uploads follow.

### Versions must be SemVer

NervesHub requires semantic versions; `PROJECT_VER` is a free-form string that
defaults to `git describe` output. Set it explicitly in your `CMakeLists.txt`:

```cmake
set(PROJECT_VER "1.2.3")
```

These shapes are accepted and normalised:

| `PROJECT_VER` | Stored as |
| --- | --- |
| `1.2.3` | `1.2.3` |
| `v1.2.3` | `1.2.3` |
| `1.2` | `1.2.0` |
| `1` | `1.0.0` |
| `1.2.3.4` | `1.2.3+4` (ESP's build counter becomes SemVer build metadata) |
| `v1.2.3-4-gabcdef` | `1.2.3-4-gabcdef` |

Anything else is rejected at upload with a message naming `PROJECT_VER`.

### Supported chips

`esp32`, `esp32s2`, `esp32s3`, `esp32c2`, `esp32c3`, `esp32c5`, `esp32c6`,
`esp32h2`, `esp32p4`. An unrecognised chip ID still uploads, recorded as
`esp32-<id>` with architecture `unknown`.

### Firmware signing

**ESP-IDF images must be signed** by default, exactly as fwup archives must be.
Register
the public half of your signing key against the organization, choosing the
**ESP-IDF Secure Boot v2 (RSA-3072)** scheme:

```bash
espsecure.py generate_signing_key --version 2 --scheme rsa3072 signing_key.pem
openssl rsa -in signing_key.pem -pubout -out signing_key_public.pem   # register this
espsecure.py sign_data --version 2 --keyfile signing_key.pem --output signed.bin app.bin
```

An image must verify against a key the organization registered, or the upload
is rejected. NervesHub deliberately ignores the public key embedded in the
signature block: verifying against that would prove only that *somebody* signed
the image, and anyone can self-sign.

A product may accept unsigned images by setting **Allow unsigned ESP-IDF
images**, which is useful while bringing a board up and before Secure Boot has
been provisioned. It applies only to images with no signature block at all —
a present-but-unverifiable signature is still refused, so the setting cannot be
used to smuggle in an image signed by an unregistered key. Firmware uploaded
this way is recorded with no signing key, and only ESP-IDF images may be left
unsigned: the database still requires an `org_key_id` for every other tool.

**ECDSA signatures are not supported.**

That block uses a different layout, and P-192/P-256/P-384 variants; such an
image is refused rather than misread.

Note that none of this affects the device. Secure Boot v2 is enforced by the
ESP32 bootloader against a key digest burned into eFuse, so an image signed with
the wrong key will not boot regardless of what NervesHub concluded. Verification
here is early failure and defence in depth, not the primary control.

## Not supported yet

### Delta updates

Deltas are generated and stored as whole-image `xdelta3` patches, but **are never
sent to devices** — `device_update_type/2` always returns `:full`. Applying a
patch requires the device to read back its inactive OTA slot and patch into it,
which no device agent does yet. Deployment groups with delta updates enabled will
still send complete images to ESP-IDF devices.

### Device connectivity

There is library in early development which you can find at 
https://github.com/nerves-hub/nerves-hub-link-esp32. 

NervesHub can store and serve ESP-IDF images, and the device protocol below is 
implemented server-side, but nothing on an ESP32 currently connects to NervesHub.

## The device protocol

A non-Nerves agent has two things to get right.

### Reporting firmware metadata on join

A Nerves device reports `nerves_fw_*` keys. An ESP-IDF device reports its
`esp_app_desc_t`, read from the running partition with
`esp_ota_get_running_partition()` and `esp_app_get_description()`:

```json
{
  "update_tool": "esp-idf",
  "esp_idf_project_name": "my_app",
  "esp_idf_version": "1.2.3",
  "esp_idf_app_elf_sha256": "ab12…",
  "esp_idf_ver": "v5.2.1",
  "esp_idf_chip_id": 9
}
```

Note that the device does **not** send a UUID. NervesHub derives it from
`app_elf_sha256` using the same rule it applied when the image was uploaded, so
an agent cannot get it subtly wrong.

`update_tool` is optional — NervesHub also recognises a device by the keys it
sends, and a device sending nothing recognisable is read as a Nerves device. 
Sending it explicitly is preferred.

### Reporting update progress

Send `update_progress` with a `value` percentage and an optional `stage`
(`downloading`, `updating`):

```json
{"value": 42, "stage": "downloading"}
```

On completion, send `firmware_validated` once the new image has proven itself.
This pairs naturally with `esp_ota_mark_app_valid_cancel_rollback()`.

Failure is reported through `status_update` with a status of `"failed"` and a
`reason`.

### VM/bootloader updates

Only the application partition is in scope. Updating the bootloader or partition
table is out of scope and would need a different mechanism.

## Implementation notes

- `NervesHub.Firmwares.UpdateTool` — the behaviour and the tool registry.
  Tools are chosen by content sniffing on upload (`for_file/1`) and by the
  recorded `firmwares.tool` column on read (`for_firmware/1`).
- `NervesHub.Firmwares.UpdateTool.EspIdf` — header parsing, version
  normalisation, signature block handling, xdelta3 deltas.
- `NervesHub.Support.EspIdf` — builds synthetic images for tests.

- `NervesHub.Products.Product.accepts_update_tool?/2` — the per-product gate.

`UpdateTool.all/0` is the set of tools an instance will *accept*, which the
`ESP_IDF_FIRMWARE_ENABLED` flag governs. `UpdateTool.known/0` is the set it can
*read*, which the flag does not: firmware already uploaded stays interpretable
after the format is turned off again, so disabling the flag stops new uploads
rather than orphaning existing ones.

The older `config :nerves_hub, :update_tool, NervesHub.Firmwares.UpdateTool.Fwup`
still works and pins an instance to exactly that one tool.
