defmodule NervesHub.Firmwares.UpdateTool.EspIdf do
  @moduledoc """
  `NervesHub.Firmwares.UpdateTool` implementation for ESP-IDF application images.

  An ESP-IDF `.bin` is an application image for the `esp_ota_*` update path: the
  device writes it into whichever of its `ota_0`/`ota_1` slots is not running,
  marks that slot bootable, and reboots — with the bootloader rolling back if the
  new image never confirms itself.

  ## Where the metadata comes from

  Unlike fwup, nothing has to be invented or bolted on. Every ESP-IDF image
  carries an `esp_app_desc_t` at a **fixed offset of 0x20**, immediately after
  `esp_image_header_t` (24 bytes) and the first `esp_image_segment_header_t`
  (8 bytes). It is 256 bytes and holds the project name, version, IDF version
  and a SHA-256 of the source ELF. The image header before it carries the chip
  ID. Between them they supply every field NervesHub enforces:

      product       <- esp_app_desc_t.project_name   (PROJECT_NAME)
      version       <- esp_app_desc_t.version        (PROJECT_VER, see below)
      uuid          <- esp_app_desc_t.app_elf_sha256 (first 16 bytes)
      platform      <- esp_image_header_t.chip_id    ("esp32s3", ...)
      architecture  <- esp_image_header_t.chip_id    ("xtensa" | "riscv")

  So there is no manifest format to design, no build-tool plugin to ship, and no
  cooperation needed from the firmware author beyond setting `PROJECT_VER` to
  something NervesHub can read as a version.

  ## Versions

  `PROJECT_VER` is a free-form 32-byte string and defaults to `git describe`
  output, while NervesHub requires strict SemVer. `normalise_version/1` accepts
  the shapes that show up in practice — a leading `v`, two-part `1.2`, and the
  four-part `1.2.3.4` that ESP tooling encourages — and anything else is
  rejected with a message pointing at `PROJECT_VER` rather than silently
  coerced into a version that would sort wrongly.

  ## Deltas

  An application image is a single opaque blob rather than an archive of
  members, so a delta is one `xdelta3` patch over the whole file. That makes
  delta generation markedly simpler than the fwup path — but note that nothing
  applies these patches on the device yet; see `device_update_type/2`.
  """

  @behaviour NervesHub.Firmwares.UpdateTool

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Firmwares.UpdateTool.Metadata
  alias NervesHub.Helpers.Logging

  require Logger

  # esp_image_header_t.magic — first byte of every ESP-IDF image.
  @image_magic 0xE9
  # esp_app_desc_t.magic_word
  @app_desc_magic 0xABCD5432
  # sizeof(esp_image_header_t) + sizeof(esp_image_segment_header_t)
  @app_desc_offset 0x20
  @app_desc_size 256
  # Enough to cover both headers in one read.
  @header_read_size @app_desc_offset + @app_desc_size

  # Secure Boot v2 appends a signature block on a 4 KB boundary after the image.
  @sig_block_magic 0xE7
  @sig_block_size 1216

  # esp_chip_id_t -> {platform, architecture}. Unknown IDs are carried through
  # rather than rejected, so a chip released after this list still uploads.
  @chip_ids %{
    0x0000 => {"esp32", "xtensa"},
    0x0002 => {"esp32s2", "xtensa"},
    0x0005 => {"esp32c3", "riscv"},
    0x0009 => {"esp32s3", "xtensa"},
    0x000C => {"esp32c2", "riscv"},
    0x000D => {"esp32c6", "riscv"},
    0x0010 => {"esp32h2", "riscv"},
    0x0012 => {"esp32p4", "riscv"},
    0x0017 => {"esp32c5", "riscv"}
  }

  @impl UpdateTool
  def tool_name(), do: "esp-idf"

  @impl UpdateTool
  def file_extension(), do: ".bin"

  @impl UpdateTool
  def recognises?(filepath) do
    case read_header(filepath) do
      {:ok, <<@image_magic, _::binary-size(0x1F), @app_desc_magic::little-32, _::binary>>} -> true
      _ -> false
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_file(filepath) do
    with {:ok, header} <- read_header(filepath),
         {:ok, parsed} <- parse_header(header),
         {:ok, version} <- normalise_version(parsed.version) do
      firmware_metadata = %Metadata{
        architecture: parsed.architecture,
        platform: parsed.platform,
        product: parsed.project_name,
        uuid: uuid_from_elf_sha256(parsed.app_elf_sha256),
        version: version,
        description: "ESP-IDF #{parsed.idf_ver}",
        author: nil,
        misc: nil,
        vcs_identifier: nil
      }

      tool_metadata = %{
        "app_elf_sha256" => Base.encode16(parsed.app_elf_sha256, case: :lower),
        "build_date" => parsed.date,
        "build_time" => parsed.time,
        "chip_id" => parsed.chip_id,
        "idf_ver" => parsed.idf_ver,
        "project_version_raw" => parsed.version,
        "secure_version" => parsed.secure_version
      }

      {:ok,
       %{
         firmware_metadata: firmware_metadata,
         tool_metadata: tool_metadata,
         tool: tool_name(),
         # The device-side agent, not the image, decides what it can apply. Until
         # `nerves_hub_link_esp_idf` has a version history worth gating on, every
         # agent is assumed capable of both.
         tool_delta_required_version: "0.0.0",
         tool_full_required_version: "0.0.0"
       }}
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_upload(firmware) do
    case download_archive(firmware) do
      {:ok, filepath} -> get_firmware_metadata_from_file(filepath)
      err -> err
    end
  end

  @impl UpdateTool
  def recognises_device_metadata?(params) do
    Map.has_key?(params, "esp_idf_app_elf_sha256") or Map.has_key?(params, "esp_idf_project_name")
  end

  @doc """
  Translate what an ESP-IDF device reports on join.

  The device reads `esp_app_desc_t` from its running partition (via
  `esp_ota_get_running_partition/0` and `esp_app_get_description/0`) and sends
  the fields verbatim under an `esp_idf_` prefix. It deliberately does **not**
  send a UUID: the mapping from `app_elf_sha256` to a NervesHub UUID is this
  module's convention, and deriving it in one place keeps a device agent from
  having to know it — and from being able to get it subtly wrong.
  """
  @impl UpdateTool
  def metadata_from_device(params) do
    {platform, architecture} = chip(params["esp_idf_chip_id"])

    %{
      uuid: device_uuid(params),
      architecture: architecture,
      platform: platform,
      product: params["esp_idf_project_name"],
      version: device_version(params["esp_idf_version"]),
      description: params["esp_idf_ver"] && "ESP-IDF #{params["esp_idf_ver"]}",
      author: nil,
      vcs_identifier: nil,
      misc: nil
    }
  end

  # An unparseable hash is not fatal: metadata_from_device/1 may still produce a
  # usable record, and a nil uuid simply means the caller cannot fall back to a
  # database lookup.
  defp device_uuid(params) do
    with sha when is_binary(sha) <- params["esp_idf_app_elf_sha256"],
         {:ok, raw} <- Base.decode16(sha, case: :mixed),
         true <- byte_size(raw) >= 16 do
      uuid_from_elf_sha256(raw)
    else
      _ -> nil
    end
  end

  defp device_version(nil), do: nil

  defp device_version(raw) do
    case normalise_version(raw) do
      {:ok, version} -> version
      {:error, _} -> nil
    end
  end

  defp chip(nil), do: {nil, nil}

  defp chip(chip_id) when is_integer(chip_id) do
    Map.get(@chip_ids, chip_id, {"esp32-#{chip_id}", "unknown"})
  end

  defp chip(chip_id) when is_binary(chip_id) do
    case Integer.parse(chip_id) do
      {id, ""} -> chip(id)
      _ -> {nil, nil}
    end
  end

  @doc """
  Parse the two headers at the front of an ESP-IDF application image.

  Public because it is the piece worth testing directly, and because reading a
  `.bin` NervesHub already stored is useful outside the upload path.
  """
  @spec parse_header(binary()) :: {:ok, map()} | {:error, term()}
  def parse_header(
        <<@image_magic, _segment_count::8, _spi_mode::8, _spi_speed_size::8, _entry_addr::little-32, _wp_pin::8,
          _spi_pin_drv::binary-size(3), chip_id::little-16, _min_chip_rev::8, _min_chip_rev_full::little-16,
          _max_chip_rev_full::little-16, _reserved::binary-size(4), hash_appended::8, _seg_load_addr::little-32,
          _seg_data_len::little-32, @app_desc_magic::little-32, secure_version::little-32, _reserv1::binary-size(8),
          version::binary-size(32), project_name::binary-size(32), time::binary-size(16), date::binary-size(16),
          idf_ver::binary-size(32), app_elf_sha256::binary-size(32), _rest::binary>>
      ) do
    {platform, architecture} = Map.get(@chip_ids, chip_id, {"esp32-#{chip_id}", "unknown"})

    {:ok,
     %{
       app_elf_sha256: app_elf_sha256,
       architecture: architecture,
       chip_id: chip_id,
       date: cstr(date),
       hash_appended: hash_appended == 1,
       idf_ver: cstr(idf_ver),
       platform: platform,
       project_name: cstr(project_name),
       secure_version: secure_version,
       time: cstr(time),
       version: cstr(version)
     }}
  end

  def parse_header(<<@image_magic, _::binary>>), do: {:error, :missing_app_descriptor}
  def parse_header(_), do: {:error, :not_an_esp_idf_image}

  @doc """
  Coerce an ESP-IDF `PROJECT_VER` string into SemVer.

  Only the unambiguous shapes are accepted. A four-part `1.2.3.4` becomes
  `1.2.3+4`: the fourth component is ESP's build counter, and build metadata is
  the one place SemVer puts something that does not affect precedence.
  """
  @spec normalise_version(String.t()) :: {:ok, String.t()} | {:error, {:invalid_version, String.t()}}
  def normalise_version(raw) do
    stripped = raw |> String.trim() |> String.trim_leading("v") |> String.trim_leading("V")

    # Try the string as-is first. `1.2.3-rc.1` is already valid SemVer and must
    # not be run through the shape rules below, which would read its four
    # dot-separated parts as ESP's major.minor.patch.build.
    candidate =
      case Version.parse(stripped) do
        {:ok, _} -> stripped
        :error -> reshape(stripped)
      end

    case Version.parse(candidate) do
      {:ok, _} -> {:ok, candidate}
      :error -> {:error, {:invalid_version, raw}}
    end
  end

  # Only ever applied to all-numeric components, so a prerelease or build suffix
  # can never be mistaken for a version component.
  defp reshape(candidate) do
    parts = String.split(candidate, ".")

    if Enum.all?(parts, &numeric?/1) do
      case parts do
        [major] -> "#{major}.0.0"
        [major, minor] -> "#{major}.#{minor}.0"
        [major, minor, patch, build] -> "#{major}.#{minor}.#{patch}+#{build}"
        _ -> candidate
      end
    else
      candidate
    end
  end

  defp numeric?(part), do: part != "" and String.match?(part, ~r/^\d+$/)

  @impl UpdateTool
  def verify_signature(filepath, keys) do
    case read_signature_block(filepath) do
      {:ok, nil} ->
        # No Secure Boot v2 block. NervesHub's `org_keys` currently only accept
        # 32-byte Ed25519 keys (see `NervesHub.Accounts.OrgKey`), which cannot
        # represent the RSA-3072/ECDSA-P256 keys Secure Boot v2 uses — so there
        # is nothing to check an ESP-IDF signature against yet, and the spike
        # accepts unsigned images. Storing ESP signing keys is its own piece of
        # work and blocks turning this into a real check.
        Logger.warning("[UpdateTool.EspIdf] accepting unsigned ESP-IDF image", filepath: filepath)
        {:ok, nil}

      {:ok, %{digest: digest} = block} ->
        with :ok <- verify_image_digest(filepath, digest) do
          match_org_key(block, keys)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl UpdateTool
  def delta_updatable?(_metadata) do
    # False until a device agent can apply a patch. Reporting `true` would make
    # deployment groups with delta updates enabled generate and store xdelta3
    # patches that `device_update_type/2` then never sends — paying for worker
    # time and object storage, and looking from the UI as though delta updates
    # were working. Flip this and `device_update_type/2` together.
    false
  end

  @impl UpdateTool
  def device_update_type(%Device{}, %Firmware{}) do
    # Deltas are generated and stored, but always sent as full images for now:
    # applying an xdelta3 patch requires the device to read back its inactive
    # OTA slot and patch into it, which the device agent does not do yet.
    # Flipping this to `:delta` is the server half of that feature and should
    # land with the agent that can honour it.
    :full
  end

  @impl UpdateTool
  def create_firmware_delta_file({_source_uuid, source_url}, {target_uuid, target_url}, work_dir) do
    source_path = Path.join(work_dir, "source.bin") |> Path.expand()
    target_path = Path.join(work_dir, "target.bin") |> Path.expand()
    delta_path = Path.join(work_dir, "#{target_uuid}.delta") |> Path.expand()

    with :ok <- File.mkdir_p(work_dir),
         :ok <- dl(source_url, source_path),
         :ok <- dl(target_url, target_path),
         {:ok, %{size: source_size}} <- File.stat(source_path),
         {:ok, %{size: target_size}} <- File.stat(target_path),
         {_, 0} <-
           System.cmd("xdelta3", ["-A", "-S", "-f", "-s", source_path, target_path, delta_path],
             stderr_to_stdout: true,
             env: []
           ),
         {:ok, %{size: delta_size}} <- File.stat(delta_path),
         {true, :delta_smaller} <- {delta_size < target_size, :delta_smaller} do
      {:ok,
       %{
         filepath: delta_path,
         size: delta_size,
         source_size: source_size,
         target_size: target_size,
         tool: tool_name(),
         tool_metadata: %{"patch_format" => "xdelta3"}
       }}
    else
      {false, :delta_smaller} ->
        {:error, :delta_larger_than_target}

      {output, status} when is_integer(status) ->
        {:error, {:xdelta3_failed, status, output}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl UpdateTool
  def cleanup_firmware_delta_files(delta_path) do
    delta_path
    |> Path.dirname()
    |> File.rm_rf()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason, _path} ->
        Logging.log_message_to_sentry("Could not cleanup delta files", %{reason: reason})
        :ok
    end
  end

  # ------------------------------------------------------------------ helpers

  defp read_header(filepath) do
    case File.open(filepath, [:read, :binary], &IO.binread(&1, @header_read_size)) do
      {:ok, data} when is_binary(data) and byte_size(data) >= @header_read_size -> {:ok, data}
      {:ok, _short_or_eof} -> {:error, :not_an_esp_idf_image}
      {:error, reason} -> {:error, reason}
    end
  end

  # `esp_app_desc_t` strings are fixed-width and NUL-padded.
  defp cstr(binary) do
    binary
    |> :binary.split(<<0>>)
    |> hd()
    |> String.trim()
  end

  # `app_elf_sha256` changes whenever the built ELF changes, which makes its
  # first 16 bytes a stable, build-derived UUID without asking the firmware
  # author to generate one.
  defp uuid_from_elf_sha256(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(6), _::binary>>
       ) do
    [a, b, c, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  # Secure Boot v2 places the signature block on the first 4 KB boundary at or
  # after the end of the image. Absent means unsigned, which is not an error.
  defp read_signature_block(filepath) do
    with {:ok, %{size: size}} <- File.stat(filepath) do
      offset = ceil(size / 4096) * 4096 - @sig_block_size

      if offset <= 0 do
        {:ok, nil}
      else
        case pread(filepath, offset, @sig_block_size) do
          {:ok,
           <<@sig_block_magic, version::8, _padding::binary-size(2), digest::binary-size(32), key::binary-size(776),
             signature::binary-size(384), _crc::little-32, _rest::binary>>} ->
            {:ok, %{digest: digest, key: key, signature: signature, version: version}}

          _ ->
            {:ok, nil}
        end
      end
    end
  end

  defp pread(filepath, offset, length) do
    File.open(filepath, [:read, :binary], fn file ->
      case :file.pread(file, offset, length) do
        {:ok, data} -> data
        other -> other
      end
    end)
    |> case do
      {:ok, data} when is_binary(data) -> {:ok, data}
      {:ok, other} -> other
      error -> error
    end
  end

  # The block's digest covers the image up to the 4 KB boundary the block sits on.
  defp verify_image_digest(filepath, expected) do
    {:ok, %{size: size}} = File.stat(filepath)
    image_length = ceil(size / 4096) * 4096 - @sig_block_size

    actual =
      filepath
      |> File.stream!(2048)
      |> Enum.reduce({:crypto.hash_init(:sha256), 0}, fn chunk, {state, read} ->
        remaining = image_length - read

        cond do
          remaining <= 0 -> {state, read}
          byte_size(chunk) <= remaining -> {:crypto.hash_update(state, chunk), read + byte_size(chunk)}
          true -> {:crypto.hash_update(state, binary_part(chunk, 0, remaining)), image_length}
        end
      end)
      |> elem(0)
      |> :crypto.hash_final()

    if actual == expected, do: :ok, else: {:error, :image_digest_mismatch}
  end

  # TODO: needs `org_keys` to be able to hold a Secure Boot v2 public key before
  # it can do anything. Left explicit rather than silently passing, so that a
  # signed image cannot be mistaken for a verified one.
  defp match_org_key(_block, _keys) do
    {:error, :esp_idf_signing_keys_not_supported}
  end

  defp download_archive(firmware) do
    {:ok, url} = firmware_upload_config().download_file(firmware)
    {:ok, archive_path} = Plug.Upload.random_file("downloaded_firmware_#{firmware.id}")

    case dl(url, archive_path) do
      :ok -> {:ok, archive_path}
      error -> error
    end
  end

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  defp dl(url, filepath) do
    response =
      Req.get!(
        url,
        [into: File.stream!(filepath)] ++ Application.get_env(:nerves_hub, :firmware_download_options, [])
      )

    if response.status == 200 do
      :ok
    else
      {:error, {:download_failed, response.status}}
    end
  rescue
    e -> {:error, {:download_failed, e}}
  end
end
