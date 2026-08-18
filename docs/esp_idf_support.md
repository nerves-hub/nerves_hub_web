# ESP-IDF Support (experimental)

NervesHub can ingest ESP-IDF application images (`.bin`) alongside fwup archives
(`.fw`). This is the first non-fwup image format it handles, and it is
**incomplete** — read the [Not supported yet](#not-supported-yet) section before
relying on it.

## What works

Upload an ESP-IDF application image through the web UI or the API exactly as you
would an fwup archive. NervesHub picks the handling tool by inspecting the file
itself, so there is nothing to configure per product and no flag to pass.

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

## Not supported yet

### Firmware signing

**ESP-IDF images are stored unsigned.** NervesHub's organization keys hold
32-byte Ed25519 public keys, which cannot represent the RSA-3072 or ECDSA-P256
keys that ESP-IDF Secure Boot v2 uses. NervesHub will parse a Secure Boot v2
signature block if one is present and check its image digest, but it has no
trusted key to verify the signature against, so it accepts the upload either way
and records no signing key. Such firmware shows as `Unsigned` in the UI.

This is a real gap in the trust chain, not a cosmetic one. Until organization
keys can hold an ESP-IDF signing key, treat upload access as equivalent to
firmware-publishing authority, and rely on device-side Secure Boot v2 (which is
enforced by the bootloader, independently of NervesHub) for image authenticity.

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

To restrict an instance to a single tool, set `config :nerves_hub, :update_tool,
NervesHub.Firmwares.UpdateTool.Fwup`. Otherwise both tools are enabled.
