defmodule NervesHub.Firmwares.UpdateTool.Rauc do
  @moduledoc """
  `NervesHub.Firmwares.UpdateTool` implementation for RAUC bundles.

  A `.raucb` is a SquashFS payload with a CMS signature appended and an
  eight-byte footer giving that signature's length:

      [ payload (squashfs, plus a dm-verity hash tree) ]
      [ CMS signature, `sigsize` bytes                 ]
      [ sigsize, big-endian uint64                     ]

  Everything this module needs is reachable from that footer, so NervesHub does
  not need `rauc` installed. That matters more than it might look: `rauc` pulls
  in glib, dbus and libcurl, and the server has no use for any of them — it
  never installs a bundle, it only reads one.

  ## Verity bundles only

  In the **verity** format the manifest lives *inside* the CMS signature, which
  is what makes a single `openssl cms -verify` both check the signature and hand
  back the manifest. In the **plain** format the signature is detached and the
  manifest is a file inside the SquashFS, which would mean unpacking a
  filesystem to read four lines of INI.

  Plain bundles are refused with a message saying so. That is not much of a
  restriction: verity is the format RAUC recommends, and it is required for the
  HTTP streaming install that is the reason to want RAUC in the first place.

  ## Signatures

  RAUC signs with CMS against an X.509 keyring, so the organization's key is a
  certificate rather than a bare public key — see
  `NervesHub.Accounts.OrgKey`. Chain verification is what CMS does; a public key
  on its own cannot anchor a chain.

  ## Metadata

  A manifest carries `compatible` and `version` and nothing else NervesHub
  requires, so the rest comes from a `[meta.nerveshub]` section:

      [update]
      compatible=acme-gateway
      version=1.4.2

      [meta.nerveshub]
      product=Gateway
      architecture=aarch64

  `compatible` stands in for `platform` and `product` when they are not given,
  because it is the closest thing RAUC has to either. `architecture` has no
  sensible default and is required, since NervesHub matches deployments on it
  and a wrong guess would send an arm64 bundle to an amd64 device.

  ## The UUID

  Declared if the manifest declares one, derived otherwise.

  A build that sets `uuid` in `[meta.nerveshub]` is naming the firmware itself,
  and that is preferred. The reason is that a *derived* uuid cannot be embedded
  in the firmware it identifies — it hashes the manifest, which records the
  rootfs's own sha256, so writing it into the image changes it. A device
  flashed by anything other than `rauc install` was therefore unable to say
  what it was running until its first update. Declaring the uuid breaks that
  circularity: the same value goes into the manifest and into the image. A
  declared value must be a UUID, because `firmware.uuid` is a UUID column.

  Without one it is derived from the SHA-256 over the manifest
  as embedded in the signature — the digest RAUC itself computes and reports as
  `hash` in `rauc info --output-format=json`. Verified against a bundle built by
  RAUC 1.13: the digest matches byte for byte.

  What NervesHub stores is the **first 128 bits of that digest**, formatted as a
  UUID, because `firmware.uuid` is a UUID column. That is a truncation, and it
  is the same truncation RAUC applies when it renders `bundle.hash` — so a
  device and NervesHub still arrive at the same string, which is the whole
  point. It does mean the stored identifier carries half the collision
  resistance of the digest it came from: 128 bits, not 256. For firmware built
  by an organization for itself that is a description rather than a concern, but
  it is a property of the identifier rather than an accident of the format.

  That identity is what makes the UUID usable, rather than merely unique. RAUC
  records the installed bundle's hash against the slot it went into
  (`bundle.hash` in its status file, which persists across reboots), so a device
  can read back what it is running with `rauc status` and arrive at the same
  UUID NervesHub recorded at upload — without NervesHub having told it.

  It is stable for identical input, so a reproducible build produces the same
  UUID, and it changes whenever anything in the manifest does, including the
  checksum of every image in the bundle.

  ## Which RAUC

  1.9 or newer, because `[meta.<label>]` sections arrived there. Older versions
  do not reject them — they drop them while rewriting the manifest into the
  signature, so a bundle built from a manifest containing `architecture=` can
  arrive without it. `metadata/1` tells that case apart from a genuinely
  incomplete manifest, because the two need different fixes and only one of them
  is in a file the author can see.

  ## Deltas

  None, and there should never be any. RAUC's saving comes from the device
  fetching only the blocks it lacks, over HTTP range requests against the whole
  bundle — see `supports_deltas?/0`.
  """

  @behaviour NervesHub.Firmwares.UpdateTool

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool

  # The squashfs magic, and therefore the first four bytes of every bundle.
  @squashfs_magic "hsqs"

  # `sizeof(guint64)`, the footer RAUC writes the signature length into.
  @footer_size 8

  # A sanity bound, not a limit RAUC imposes. It exists so that a corrupt footer
  # asks for a plausible allocation rather than an enormous one.
  @max_signature_size 64 * 1024 * 1024

  # The oldest RAUC a device can run and still be usable here.
  #
  # 1.8 installs a verity bundle perfectly well, so this is not about the
  # format. It is about identity: `bundle.hash` — the field a device reads back
  # to say which firmware it is running — was added to slot status in **1.9**.
  # A 1.8 device installs, reboots, and then cannot answer the one question
  # NervesHub asks it.
  #
  # The same 1.9 is needed to *build* a readable bundle, for an unrelated
  # reason: older versions drop `[meta.<label>]` while signing. Two different
  # requirements landing on one version is a coincidence, not a rule, so both
  # are stated where they apply.
  @minimum_device_version "1.9.0"

  @impl UpdateTool
  def tool_name(), do: "rauc"

  @impl UpdateTool
  def file_extension(), do: ".raucb"

  @impl UpdateTool
  def recognises?(filepath) do
    case File.open(filepath, [:read, :binary], &IO.binread(&1, 4)) do
      {:ok, @squashfs_magic} -> true
      _ -> false
    end
  end

  @impl UpdateTool
  def verify_signature(filepath, keys) do
    # Only certificates are RAUC trust anchors. An org may also hold fwup
    # Ed25519 keys and ESP secure-boot RSA keys, and handing either to
    # `openssl cms` would fail in a way that reads like a bad bundle.
    case Enum.filter(keys, &(&1.scheme == :x509_certificate)) do
      [] -> {:error, :no_public_keys}
      candidates -> find_signing_key(filepath, candidates)
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_file(filepath) do
    with {:ok, manifest} <- extract_manifest(filepath) do
      metadata(manifest)
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_upload(%Firmware{} = firmware) do
    {:ok,
     %{
       firmware_metadata: %UpdateTool.Metadata{
         architecture: firmware.architecture,
         platform: firmware.platform,
         product: firmware.product,
         uuid: firmware.uuid,
         version: firmware.version,
         author: firmware.author,
         description: firmware.description,
         misc: firmware.misc,
         vcs_identifier: firmware.vcs_identifier
       },
       tool_metadata: firmware.tool_metadata || %{},
       tool: tool_name(),
       tool_delta_required_version: firmware.tool_delta_required_version || @minimum_device_version,
       tool_full_required_version: firmware.tool_full_required_version || @minimum_device_version
     }}
  end

  @doc """
  RAUC bundles are never delta updated by NervesHub.

  The device fetches only the blocks its target slot does not already have,
  using HTTP range requests against the bundle itself. Generating a patch would
  cost worker time and object storage to produce something nothing would ever
  ask for.
  """
  @impl UpdateTool
  def supports_deltas?(), do: false

  @impl UpdateTool
  def delta_updatable?(_metadata), do: false

  @impl UpdateTool
  def create_firmware_delta_file(_source, _target, _work_dir) do
    {:error, :deltas_not_supported}
  end

  @impl UpdateTool
  def cleanup_firmware_delta_files(_path), do: :ok

  @impl UpdateTool
  def device_update_type(%Device{}, %Firmware{}), do: :full

  @impl UpdateTool
  def recognises_device_metadata?(params), do: Map.has_key?(params, "rauc_compatible")

  @impl UpdateTool
  def metadata_from_device(params) do
    %{
      uuid: params["rauc_uuid"],
      architecture: params["rauc_architecture"],
      platform: params["rauc_platform"] || params["rauc_compatible"],
      product: params["rauc_product"] || params["rauc_compatible"],
      version: params["rauc_version"],
      author: nil,
      description: nil,
      fwup_version: nil,
      vcs_identifier: nil,
      misc: nil
    }
  end

  # ---------------------------------------------------------------------------

  @doc """
  Read the CMS signature out of a bundle, using the footer to find it.

  Public because it is the only part of the format this module reads directly,
  and a test that cannot reach it has to construct a whole bundle to check the
  arithmetic.
  """
  @spec read_signature(String.t()) :: {:ok, binary()} | {:error, term()}
  def read_signature(filepath) do
    with {:ok, %{size: size}} <- File.stat(filepath),
         true <- size > @footer_size || {:error, :not_a_bundle},
         {:ok, file} <- File.open(filepath, [:read, :binary]) do
      try do
        with {:ok, <<sigsize::unsigned-big-integer-size(64)>>} <-
               :file.pread(file, size - @footer_size, @footer_size),
             :ok <- validate_signature_size(sigsize, size) do
          # `:truncated_bundle` is not reachable from any sequence of bytes:
          # `validate_signature_size/2` rejects every footer that would read off
          # the end before a read happens, and the ordering that guarantees that
          # is pinned by "each class of bad footer gets its own error".
          #
          # What is left is the window between `File.stat/1` above and this
          # read — a file that shrinks underneath an upload in progress. The
          # clause stays for that: without it `pread` returning `:eof` would
          # raise `CaseClauseError` inside an upload, which is a worse way to
          # find out than a failed upload with a reason.
          case :file.pread(file, size - @footer_size - sigsize, sigsize) do
            {:ok, signature} -> {:ok, signature}
            :eof -> {:error, :truncated_bundle}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, reason} -> {:error, reason}
          # Includes `:eof` and a short read, both of which mean the footer is
          # not eight readable bytes.
          _ -> {:error, :not_a_bundle}
        end
      after
        File.close(file)
      end
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :not_a_bundle}
    end
  end

  defp validate_signature_size(0, _size), do: {:error, :no_signature}

  defp validate_signature_size(sigsize, size) when sigsize > size - @footer_size do
    {:error, :signature_exceeds_bundle}
  end

  defp validate_signature_size(sigsize, _size) when sigsize > @max_signature_size do
    {:error, :implausible_signature_size}
  end

  defp validate_signature_size(_sigsize, _size), do: :ok

  defp find_signing_key(filepath, keys) do
    with {:ok, signature} <- read_signature(filepath) do
      attempts =
        Enum.map(keys, fn %OrgKey{key: certificate} = key ->
          {key, verify_cms(signature, certificate)}
        end)

      case Enum.find(attempts, fn {_key, result} -> match?({:ok, _manifest}, result) end) do
        {%OrgKey{} = key, _result} ->
          {:ok, key}

        nil ->
          no_key_matched(attempts)
      end
    end
  end

  # "This certificate cannot sign anything" and "this certificate did not sign
  # this bundle" are different problems, and only one of them is fixed by
  # uploading a different file. Reported separately so the message points at
  # the key rather than at the bundle.
  defp no_key_matched(attempts) do
    if Enum.any?(attempts, fn {_key, result} -> unsuitable_purpose?(result) end) do
      {:error, :unsuitable_certificate_purpose}
    else
      {:error, :invalid_signature}
    end
  end

  # openssl's own wording. It comes from its error table rather than a locale,
  # which is what makes matching on it reasonable.
  defp unsuitable_purpose?({:error, {:openssl_failed, _status, output}}) do
    String.contains?(output, "unsuitable certificate purpose")
  end

  defp unsuitable_purpose?(_result), do: false

  @doc """
  The manifest, as text.

  Extracted *without* checking the signer's chain: which key signed a bundle is
  `verify_signature/2`'s question, and metadata is read on a path that has no
  keys to hand. The signature over the content is still checked, so the manifest
  cannot have been altered after signing.
  """
  @spec extract_manifest(String.t()) :: {:ok, String.t()} | {:error, term()}
  def extract_manifest(filepath) do
    with {:ok, signature} <- read_signature(filepath) do
      verify_cms(signature, nil)
    end
  end

  # `certificate` nil skips chain verification and only extracts.
  defp verify_cms(signature, certificate) do
    in_tmp(fn dir ->
      cms_path = Path.join(dir, "signature.der")
      out_path = Path.join(dir, "manifest.raucm")

      with {:ok, openssl} <- openssl_executable(),
           :ok <- File.write(cms_path, signature),
           {:ok, args} <- openssl_args(dir, cms_path, out_path, certificate),
           {_output, 0} <- System.cmd(openssl, args, stderr_to_stdout: true, env: []),
           {:ok, manifest} <- File.read(out_path) do
        # Belt and braces: openssl usually refuses a detached signature outright
        # (below), but an empty manifest is not one either way.
        if String.trim(manifest) == "" do
          {:error, :plain_bundle_unsupported}
        else
          {:ok, manifest}
        end
      else
        {output, status} when is_integer(status) ->
          classify(String.trim(to_string(output)), status)

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  # `System.cmd/3` raises when the executable is not on the path, rather than
  # returning an error like everything else on this path does — and an
  # `ErlangError` surfacing from an upload reads as a bug in NervesHub rather
  # than as a missing package.
  #
  # Not a live risk: the runtime image installs `openssl`. It is handled because
  # the shell-out is a runtime dependency that nothing else in NervesHub has,
  # and "openssl is not installed" is worth saying out loud when it is true.
  defp openssl_executable() do
    case System.find_executable("openssl") do
      nil -> {:error, :openssl_not_available}
      path -> {:ok, path}
    end
  end

  # A detached CMS has nothing to extract, and openssl says so in as many words.
  #
  # Matching on the message is not lovely, but the alternative is decoding the
  # CMS ourselves to find out whether it has an eContent — a lot of ASN.1 to
  # answer a question openssl has already answered. The string comes from
  # openssl's own error table rather than a locale, so it is stabler than it
  # looks, and anything unrecognised still surfaces verbatim.
  defp classify(output, status) do
    if String.contains?(output, "no content") do
      {:error, :plain_bundle_unsupported}
    else
      {:error, {:openssl_failed, status, output}}
    end
  end

  defp openssl_args(_dir, cms_path, out_path, nil) do
    {:ok,
     [
       "cms",
       "-verify",
       "-inform",
       "DER",
       "-in",
       cms_path,
       "-out",
       out_path,
       # Chain verification is deliberately skipped here. See extract_manifest/1.
       "-noverify"
     ]}
  end

  defp openssl_args(dir, cms_path, out_path, certificate) do
    ca_path = Path.join(dir, "ca.pem")

    with :ok <- File.write(ca_path, certificate) do
      {:ok,
       [
         "cms",
         "-verify",
         "-inform",
         "DER",
         "-in",
         cms_path,
         "-out",
         out_path,
         "-CAfile",
         ca_path,
         # `-CAfile` reads as "trust exactly this certificate" and is not that.
         # It suppresses openssl's default CA *file* and leaves the default CA
         # directory — and, on 3.x, the default CA store — in play. Without the
         # two flags below, a bundle whose signer chains to any root the host
         # happens to trust verifies against an organization that never issued
         # it, which is every public CA on a stock Ubuntu image.
         #
         # So these, not `-CAfile`, are what scope trust to the org's keyring.
         "-no-CApath",
         "-no-CAstore"
         # No `-purpose any` here, deliberately.
         #
         # RAUC verifies a bundle with CMS_verify, which applies openssl's
         # default S/MIME signing purpose. Relaxing it here made NervesHub
         # accept bundles no device could install: a certificate carrying
         # `extendedKeyUsage=codeSigning` -- the obvious choice for firmware --
         # passes `-purpose any` and is then refused on every device with
         # "unsuitable certificate purpose", mid-install.
         #
         # A certificate with no EKU is valid for every purpose and passes the
         # default check, which is the ordinary case and needs no help. So the
         # flag only ever admitted certificates that were going to fail later,
         # somewhere far more expensive than an upload.
       ]}
    end
  end

  defp metadata(manifest) do
    sections = parse_manifest(manifest)

    update = Map.get(sections, "update", %{})
    ours = Map.get(sections, "meta.nerveshub", %{})

    compatible = Map.get(update, "compatible")

    with {:ok, compatible} <- required(compatible, "[update] compatible"),
         {:ok, version} <- required(Map.get(update, "version"), "[update] version"),
         {:ok, architecture} <- required_meta(ours, "architecture"),
         {:ok, uuid} <- uuid(ours, manifest) do
      {:ok,
       %{
         firmware_metadata: %UpdateTool.Metadata{
           architecture: architecture,
           platform: Map.get(ours, "platform", compatible),
           product: Map.get(ours, "product", compatible),
           uuid: uuid,
           version: version,
           author: Map.get(ours, "author"),
           description: Map.get(update, "description"),
           misc: Map.get(ours, "misc"),
           vcs_identifier: Map.get(update, "build")
         },
         tool_metadata: %{
           "compatible" => compatible,
           "bundle_format" => sections |> Map.get("bundle", %{}) |> Map.get("format", "verity")
         },
         tool: tool_name(),
         # Never consulted: `supports_deltas?/0` is false, so nothing asks
         # whether a device is new enough to apply a patch that is never built.
         # It is set because the column is not nullable.
         tool_delta_required_version: @minimum_device_version,
         tool_full_required_version: @minimum_device_version
       }}
    end
  end

  # Declared if the manifest declares one, derived otherwise.
  #
  # A derived uuid cannot be embedded in the firmware it identifies: it hashes
  # the manifest, which records the rootfs's own sha256, so writing it into the
  # image would change it. That left a device flashed by anything other than
  # `rauc install` — UUU or dd at a factory — unable to say what it was running
  # until its first update, which is a poor default for a fleet.
  #
  # A build that sets `uuid` in `[meta.nerveshub]` writes the same value into
  # the manifest and into the image, so the device knows its identity from its
  # first boot however it was flashed. Both sides then name the same firmware,
  # which is what `firmware.uuid` has to match for a device to be recognised.
  defp uuid(ours, manifest) do
    case Map.get(ours, "uuid") do
      nil ->
        {:ok, uuid_from_manifest(manifest)}

      declared ->
        # `firmware.uuid` is a UUID column, so a declared value that is not one
        # would fail later as a cast error against a changeset, well away from
        # the manifest that caused it.
        case Ecto.UUID.cast(declared) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, {:invalid_manifest_field, "[meta.nerveshub] uuid"}}
        end
    end
  end

  defp required(nil, what), do: {:error, {:missing_manifest_field, what}}
  defp required("", what), do: {:error, {:missing_manifest_field, what}}
  defp required(value, _what), do: {:ok, value}

  # A missing `[meta.nerveshub]` section and a missing key inside it are
  # different problems, and the difference is almost always the version of rauc
  # that built the bundle.
  #
  # `[meta.<label>]` arrived in RAUC 1.9. Older versions do not reject the
  # section — they drop it while rewriting the manifest into the signature, so
  # a bundle built with the field present arrives without it. Reporting that as
  # "add architecture" sends someone to look at a file that already says
  # `architecture=`.
  defp required_meta(meta, key) when map_size(meta) == 0 do
    {:error, {:missing_manifest_section, key}}
  end

  defp required_meta(meta, key) do
    required(Map.get(meta, key), "[meta.nerveshub] #{key}")
  end

  @doc """
  The UUID NervesHub records, from a SHA-256 over the manifest.

  The **first 128 bits** of that digest, formatted as a UUID — RAUC's own
  truncated rendering of `bundle.hash`, not the full digest. Matching RAUC's
  truncation is what lets a device work out what it is running without being
  told; see the module documentation for what the truncation costs.
  """
  @spec uuid_from_manifest(String.t()) :: String.t()
  def uuid_from_manifest(manifest) do
    <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(6), _::binary>> =
      :crypto.hash(:sha256, manifest)

    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end

  @doc """
  Parse a manifest into `%{"section" => %{"key" => "value"}}`.

  The format is GLib's key file: INI, `#` comments, and values that are not
  quoted. Written here rather than pulled in, because the whole of it is the
  twenty lines below and a dependency would be harder to read.
  """
  @spec parse_manifest(String.t()) :: %{String.t() => %{String.t() => String.t()}}
  def parse_manifest(manifest) do
    manifest
    |> String.split(["\n", "\r\n"])
    |> Enum.reduce({nil, %{}}, fn line, {section, sections} ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, "#") ->
          {section, sections}

        String.starts_with?(line, "[") and String.ends_with?(line, "]") ->
          name = line |> String.slice(1..-2//1) |> String.trim()
          {name, Map.put_new(sections, name, %{})}

        section != nil ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = String.trim(key)
              value = String.trim(value)
              # Last value wins, which is what GLib's key file says and what
              # RAUC itself would read. Building the map by prepending the new
              # entry and calling `Map.new/1` did the opposite, because
              # `Map.new/1` keeps the *last* occurrence of a duplicate key and
              # the older entry came after it in the list.
              {section, Map.update(sections, section, %{key => value}, &Map.put(&1, key, value))}

            _ ->
              {section, sections}
          end

        true ->
          {section, sections}
      end
    end)
    |> elem(1)
  end

  defp in_tmp(fun) do
    # `Briefly` rather than a hand-rolled name: it is what the rest of NervesHub
    # already uses for scratch directories (see
    # `Firmwares.do_generate_firmware_delta/3`), the name it picks carries 20
    # random bytes, and it reaps the directory if this process dies before the
    # `after` below gets to run.
    #
    # Two things are still done by hand, because Briefly's defaults are not what
    # this directory needs.
    case Briefly.create(type: :directory) do
      {:ok, dir} ->
        try do
          # Briefly creates its per-process root 0755 and leaves the directory
          # inside it at whatever the umask gives. `ca.pem` is written in here,
          # and that file is what tells openssl who to trust, so the rest of the
          # machine has no business reading or replacing it.
          with :ok <- File.chmod(dir, 0o700) do
            fun.(dir)
          end
        after
          # Deliberately not `Briefly.cleanup/0`, which removes every Briefly
          # path the *calling process* owns. During an upload that includes the
          # firmware file itself, which `BrieflyUploadWriter` hands to this
          # process — cleaning up here would delete the bundle being verified.
          #
          # Briefly's own reaping is tied to process exit, and a LiveView
          # outlives many uploads, so without this the signature copies would
          # sit in the temp directory until the operator navigated away. One
          # copy is written per organization certificate tried.
          File.rm_rf(dir)
        end

      {:error, reason} ->
        {:error, {:temp_dir_unavailable, reason}}
    end
  end
end
