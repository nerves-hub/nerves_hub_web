# ESP-IDF Support (experimental)

NervesHub can ingest ESP-IDF application images (`.bin`) alongside fwup archives
(`.fw`). Support is experimental and incomplete — see
[Limitations](#limitations).

## Enabling it

Support is off by default, and is turned on in two places: once for the
instance, and once for each product that should accept the format.

### 1. The instance

Set `ESP_IDF_FIRMWARE_ENABLED=true`. Without it, no `.bin` is recognised and no
product can opt in.

### 2. The product

Under **Product → Settings → Firmware**:

| Setting | Column | Default |
| --- | --- | --- |
| Accept ESP-IDF application images | `products.allowed_update_tools` | `["fwup"]` |
| Allow unsigned ESP-IDF images | `products.allow_unsigned_esp_idf_firmware` | `false` |

A product accepts only the formats listed in `allowed_update_tools`; fwup is
always among them. Uploading a `.bin` to a product that has not opted in is
rejected with a message naming the product.

**Allow unsigned ESP-IDF images** applies only to images with no signature block
at all. An image that carries a signature is always verified against the
organization's registered keys, whether or not the setting is on. See
[Firmware signing](#firmware-signing).

Turning acceptance off leaves the unsigned setting as it was.

### Over the API

Both settings are on the product resource, and are settable with `PUT` or
`PATCH` (org role `manage`):

```bash
curl -X PATCH \
  -H "Authorization: token $NH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"allowed_update_tools": ["fwup", "esp-idf"]}' \
  https://<host>/api/orgs/<org>/products/<product>
```

`require_unique_firmware_version`, `allowed_update_tools`, and
`allow_unsigned_esp_idf_firmware` can be set. Any other field returns a 422,
including `name` — a product cannot be renamed this way, as its name identifies
it in every URL. Listing a tool the instance has not enabled also returns a 422.

## Uploading

Upload an ESP-IDF application image through the web UI or the API exactly as you
would an fwup archive. NervesHub identifies the format by inspecting the file
rather than by its extension, then checks it against the product's
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

NervesHub requires semantic versions. `PROJECT_VER` is a free-form string that
defaults to `git describe` output, so set it explicitly in your
`CMakeLists.txt`:

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

## Firmware signing

ESP-IDF images must be signed, as fwup archives must be. Register the public
half of your signing key against the organization, choosing the **ESP-IDF Secure
Boot v2 (RSA-3072)** scheme:

```bash
espsecure.py generate_signing_key --version 2 --scheme rsa3072 signing_key.pem
openssl rsa -in signing_key.pem -pubout -out signing_key_public.pem   # register this
espsecure.py sign_data --version 2 --keyfile signing_key.pem --output signed.bin app.bin
```

An image must verify against a key the organization registered, or the upload is
rejected. The public key embedded in the signature block is ignored — it proves
only that somebody signed the image, and anyone can self-sign.

A product can accept unsigned images with **Allow unsigned ESP-IDF images**,
which is useful during board bring-up, before Secure Boot has been provisioned.
Such firmware is recorded with no signing key. Only ESP-IDF images may be left
unsigned; every other format still requires one.

ECDSA signature blocks (P-192/P-256/P-384) use a different layout and are not
supported. Such an image is refused rather than misread.

Signing does not affect the device. Secure Boot v2 is enforced by the ESP32
bootloader against a key digest burned into eFuse, so an image signed with the
wrong key will not boot regardless of what NervesHub concluded.

## Limitations

### Delta updates

Deltas are generated and stored as whole-image `xdelta3` patches, but are never
sent to devices — ESP-IDF firmware always updates in full. Applying a patch
requires a device to read back its inactive OTA slot and patch into it, which no
device agent does yet. Deployment groups with delta updates enabled still send
complete images to ESP-IDF devices.

### Device connectivity

NervesHub can store and serve ESP-IDF images, and the device protocol below is
implemented server-side. A client library for the device is in early development
at https://github.com/nerves-hub/nerves-hub-link-esp32.

### VM and bootloader updates

Only the application partition is in scope. Updating the bootloader or partition
table needs a different mechanism.

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

The device does not send a UUID. NervesHub derives it from `app_elf_sha256`
using the same rule it applied when the image was uploaded.

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
This pairs with `esp_ota_mark_app_valid_cancel_rollback()`.

Failure is reported through `status_update` with a status of `"failed"` and a
`reason`.
