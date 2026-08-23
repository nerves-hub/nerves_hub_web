defmodule NervesHub.Firmwares.UpdateTool.AtomVM do
  @moduledoc """
  `NervesHub.Firmwares.UpdateTool` implementation for AtomVM packbeam archives.

  An AtomVM `.avm` is a packbeam: a flat archive of compiled BEAM modules and
  data files that the VM mounts and runs directly. It is not a system image.
  Where an ESP-IDF `.bin` replaces everything running on the device, a packbeam
  replaces only the application — the VM underneath it is updated separately, if
  at all.

  ## Format

  The file opens with 24 bytes that double as a shebang, so a packbeam marked
  executable runs under AtomVM:

      #!/usr/bin/env AtomVM\\n\\0\\0

  Entries follow until a zeroed size/flags pair terminates the archive. Each is
  a 12 byte header — size, flags, reserved, all big endian — then a NUL
  terminated name padded to a 4 byte boundary, then the data. `size` covers the
  whole entry, header included, so walking is `offset + size`.

  ## Where the metadata comes from

  A packbeam carries OTP application metadata as a data entry named
  `<app>/priv/application.bin`, holding a 4 byte length and then an
  `{application, Name, Props}` term in Erlang's external term format. Between
  the name and `Props` it supplies what NervesHub needs:

      product       <- Name
      version       <- Props[:vsn]
      description   <- Props[:description]
      uuid          <- SHA-256 of the packbeam, first 16 bytes

  There is no `.app` source file in the archive and no chip or board identifier
  anywhere in it — a packbeam is portable bytecode, so `platform` and
  `architecture` describe the runtime rather than the silicon. A packbeam that
  calls `esp:` NIFs is of course not portable in practice; that distinction
  belongs to the product, which is the level at which a device family is already
  modelled.

  ## Which application

  A packbeam built from a project with dependencies contains one
  `application.bin` per application, and nothing in the file marks which is the
  root — `atomvm_packbeam` has to be *told*, via its `application_module`
  option. NervesHub takes the first, which is the project's own: the plugin
  builds its file list as

      reorder_beamfiles(BeamFiles) ++ AppFileBinFiles ++ BootFiles ++ PrivFilesRelative ++ AvmFiles

  with the dependency archives last, and `packbeam_api:create/3` writes entries
  in list order. An archive assembled by hand in some other order would be read
  wrongly, and would show up as firmware filed under a dependency's name.

  ## Terms

  The application term is decoded by this module rather than by
  `:erlang.binary_to_term/2`. Decoding an uploaded file with `binary_to_term`
  creates an atom per distinct atom in the term, and atoms are never collected —
  a single crafted archive could exhaust the table. `:safe` is not a way out,
  because the whole point is to read an application name the server has never
  seen. `decode_term/1` handles the small subset an application spec uses and
  returns every atom as a string.

  ## Signatures

  The packbeam format has no signature of its own: `atomvm_packbeam` writes
  none and `avmpack_is_valid` compares the 24 byte magic and nothing else. So
  one is added as a convention, in the shape fwup uses — the signature travels
  inside the archive, as a sibling of what it signs.

      magic
      entry, entry, ...                 the archive as built
      nerves_hub/signature   (data)     appended
      terminator

  The signed range is every byte before the signature entry begins, which is
  the one rule such a scheme has to get right: the signed bytes must exclude
  the signature, or it cannot be checked without knowing what it was. Because
  the signature is appended, nothing before it moves, and both ends compute the
  same range without agreeing on anything else.

  The signature is Ed25519 over that range, and the key is the organization's
  existing fwup key. An fwup private key is a 32 byte seed followed by its
  public key, and the public half is byte for byte what NervesHub already
  stores — so an organization signs AtomVM firmware with the key it already
  has, and this verifies against the key it already holds.

  A signed archive still boots on a stock AtomVM: the entry is a data file, the
  class the VM skips when it looks for code. Signing can only add a check,
  never take a device away.

  See `nh_signature` and the `nh-avm` tool in `nerves_hub_link_atomvm_esp32`,
  which produce this and which the device uses to verify before it installs.

  Unsigned archives are still accepted, because nothing in the wider AtomVM
  toolchain signs by default; see `verify_signature/2`.

  ## Deltas

  `supports_deltas?/0` is false. Nothing on an AtomVM device applies a patch:
  there is no equivalent of `esp_delta_ota`, and the update path writes a whole
  packbeam into an inactive partition. Reporting false here means no patch is
  ever generated, rather than generating one nothing can apply — see
  `c:NervesHub.Firmwares.UpdateTool.supports_deltas?/0`.
  """

  @behaviour NervesHub.Firmwares.UpdateTool

  alias NervesHub.Devices.Device
  alias NervesHub.Firmwares.Firmware
  alias NervesHub.Firmwares.UpdateTool
  alias NervesHub.Firmwares.UpdateTool.Metadata

  # The 24 bytes `avmpack_is_valid` compares. A shebang so that a packbeam
  # marked executable runs, NUL padded to a 4 byte boundary.
  @magic <<"#!/usr/bin/env AtomVM\n", 0, 0>>
  @magic_size byte_size(@magic)

  # size, flags, reserved — all big endian, all 4 bytes.
  @entry_header_size 12

  # A packbeam is bytecode for a VM, not an image for a chip. Both sides report
  # these verbatim so that a device and its firmware match.
  @platform "atomvm"
  @architecture "beam"

  # An application spec is a few hundred bytes in practice. The cap stops a
  # crafted archive from handing the term decoder something enormous.
  @max_application_entry_size 64 * 1024

  # Where a signature lives, and the shape of what is in it. Namespaced so it
  # cannot collide with a scheme AtomVM may define, and versioned so that one
  # would be additive.
  @signature_entry "nerves_hub/signature"
  @signature_version 1

  @impl UpdateTool
  def tool_name(), do: "atomvm"

  @impl UpdateTool
  def file_extension(), do: ".avm"

  @impl UpdateTool
  def recognises?(filepath) do
    case File.open(filepath, [:read, :binary], &IO.binread(&1, @magic_size)) do
      {:ok, @magic} -> true
      _ -> false
    end
  end

  @doc """
  Verify a packbeam's signature, if it carries one.

  An archive with no signature entry is accepted with no key. Nothing in the
  AtomVM toolchain signs by default, so refusing unsigned archives here would
  refuse every archive built by anything but this project's own tooling.
  Requiring signatures is a product-level decision to make later, in the shape
  `allow_unsigned_esp_idf_firmware` already has.

  An archive that *is* signed is verified, and a bad signature is refused
  whatever the product allows.
  """
  @impl UpdateTool
  def verify_signature(filepath, keys) do
    with {:ok, binary} <- File.read(filepath),
         {:ok, entries} <- entries(binary) do
      case Enum.find(entries, &(&1.name == @signature_entry)) do
        nil ->
          {:ok, nil}

        %{offset: offset, data: payload} ->
          # Everything before the signature entry begins. See
          # `nh_signature` in nerves_hub_link_atomvm_esp32.
          verify_payload(binary_part(binary, 0, offset), payload, keys)
      end
    end
  end

  defp verify_payload(signed, <<"NH1", @signature_version::8, signature::binary-size(64)>>, keys) do
    keys
    |> Enum.filter(&(&1.scheme == :ed25519))
    |> Enum.find(&verifies?(signed, signature, &1))
    |> case do
      nil -> {:error, :invalid_signature}
      key -> {:ok, key}
    end
  end

  defp verify_payload(_signed, <<"NH1", version::8, _rest::binary>>, _keys) do
    {:error, {:unsupported_signature_version, version}}
  end

  defp verify_payload(_signed, _payload, _keys), do: {:error, :malformed_signature}

  # An organization's Ed25519 key is stored the way fwup writes it: base64 of
  # the 32 raw bytes. The same key signs both formats.
  defp verifies?(signed, signature, %{key: key}) do
    case decode_public_key(key) do
      {:ok, public} -> :crypto.verify(:eddsa, :none, signed, signature, [public, :ed25519])
      :error -> false
    end
  rescue
    # A key that is the right length but not a point on the curve fails this
    # candidate, not the upload.
    _ -> false
  end

  defp decode_public_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> Base.decode64()
    |> case do
      {:ok, <<public::binary-size(32)>>} -> {:ok, public}
      _ -> :error
    end
  end

  defp decode_public_key(_key), do: :error

  @impl UpdateTool
  def get_firmware_metadata_from_file(filepath) do
    with {:ok, binary} <- File.read(filepath),
         {:ok, entries} <- entries(binary),
         {:ok, application} <- application_spec(entries),
         {:ok, raw_version} <- fetch_property(application.properties, "vsn"),
         {:ok, version} <- normalise_version(raw_version) do
      digest = :crypto.hash(:sha256, binary)

      firmware_metadata = %Metadata{
        architecture: @architecture,
        platform: @platform,
        product: application.name,
        uuid: uuid_from_digest(digest),
        version: version,
        description: property(application.properties, "description"),
        author: nil,
        misc: nil,
        vcs_identifier: nil
      }

      tool_metadata = %{
        "avm_sha256" => Base.encode16(digest, case: :lower),
        "application_vsn_raw" => raw_version,
        "module_count" => Enum.count(entries, &String.ends_with?(&1.name, ".beam")),
        "packbeam_size" => byte_size(binary)
      }

      {:ok,
       %{
         firmware_metadata: firmware_metadata,
         tool_metadata: tool_metadata,
         tool: tool_name(),
         # The device agent decides what it can apply, not the archive. There is
         # one version of `nerves_hub_link_atomvm_esp32` so far and nothing to
         # gate on yet.
         tool_delta_required_version: "0.0.0",
         tool_full_required_version: "0.0.0"
       }}
    end
  end

  @impl UpdateTool
  def get_firmware_metadata_from_upload(firmware) do
    case download_archive(firmware) do
      {:ok, filepath} -> get_firmware_metadata_from_file(filepath)
      error -> error
    end
  end

  @impl UpdateTool
  def recognises_device_metadata?(params) do
    Map.has_key?(params, "atomvm_app_name") or Map.has_key?(params, "atomvm_avm_sha256")
  end

  @doc """
  Translate what an AtomVM device reports on join.

  The device reads its own application metadata out of the packbeam it booted
  and sends it under an `atomvm_` prefix, along with
  `erlang:system_info(atomvm_version)` — the VM's version, which no archive can
  know and which is updated on a separate schedule from the application.

  As with ESP-IDF, the device sends a hash rather than a UUID. Deriving the UUID
  from it is this module's convention, and keeping that derivation in one place
  stops a device agent from having to know it, or from getting it subtly wrong.
  A device that does not hash its partition simply reports no UUID; that costs
  it the database fallback in `NervesHub.Firmwares.metadata_from_device/2` when
  the rest of its metadata is incomplete.
  """
  @impl UpdateTool
  def metadata_from_device(params) do
    %{
      uuid: device_uuid(params),
      architecture: @architecture,
      platform: @platform,
      product: params["atomvm_app_name"],
      version: device_version(params["atomvm_app_version"]),
      description: params["atomvm_version"] && "AtomVM #{params["atomvm_version"]}",
      author: nil,
      vcs_identifier: nil,
      misc: nil
    }
  end

  # Nothing on an AtomVM device applies a patch. See the "Deltas" section above.
  @impl UpdateTool
  def supports_deltas?(), do: false

  @impl UpdateTool
  def delta_updatable?(_metadata), do: false

  @impl UpdateTool
  def device_update_type(%Device{}, %Firmware{}), do: :full

  @impl UpdateTool
  def create_firmware_delta_file(_source, _target, _work_dir), do: {:error, :deltas_not_supported}

  @impl UpdateTool
  def cleanup_firmware_delta_files(_delta_path), do: :ok

  @doc """
  Walk a packbeam, returning every entry in file order.

  Public because it is the piece worth testing directly, and because listing an
  archive NervesHub already stored is useful outside the upload path.
  """
  @spec entries(binary()) :: {:ok, [%{name: String.t(), flags: non_neg_integer(), data: binary()}]} | {:error, term()}
  def entries(<<@magic, rest::binary>>), do: walk(rest, [])
  def entries(_), do: {:error, :not_a_packbeam}

  # A zero size or a zero flags word terminates the archive.
  defp walk(binary, acc), do: walk(binary, @magic_size, acc)

  defp walk(<<0::32, _::binary>>, _offset, acc), do: {:ok, Enum.reverse(acc)}
  defp walk(<<_size::32, 0::32, _::binary>>, _offset, acc), do: {:ok, Enum.reverse(acc)}

  defp walk(<<size::32, flags::32, _reserved::32, _::binary>> = binary, offset, acc) when size > @entry_header_size do
    case binary do
      <<entry::binary-size(^size), rest::binary>> ->
        body = binary_part(entry, @entry_header_size, size - @entry_header_size)

        case split_name(body) do
          {:ok, name, data} ->
            # The offset is what a signature needs: the signed range ends where
            # the signature entry begins.
            walk(rest, offset + size, [
              %{name: name, flags: flags, data: data, offset: offset} | acc
            ])

          :error ->
            {:error, :malformed_packbeam_entry}
        end

      _ ->
        {:error, :truncated_packbeam}
    end
  end

  # Anything else — a size that cannot hold its own header, or a trailing
  # fragment too short to read — is a malformed archive rather than the end of
  # a well formed one.
  defp walk(_, _offset, _acc), do: {:error, :malformed_packbeam_entry}

  # The name is NUL terminated and padded so the data that follows starts on a
  # 4 byte boundary, measured from the start of the entry.
  defp split_name(body) do
    case :binary.match(body, <<0>>) do
      {position, 1} ->
        padded = div(position + 1 + 3, 4) * 4

        if byte_size(body) >= padded do
          {:ok, binary_part(body, 0, position), binary_part(body, padded, byte_size(body) - padded)}
        else
          :error
        end

      :nomatch ->
        :error
    end
  end

  # `atomvm_packbeam` identifies an application spec by the entry name splitting
  # into exactly three components, so this matches the same shape rather than
  # any path that happens to end the same way.
  defp application_entry?(%{name: name}) do
    match?([_app, "priv", "application.bin"], String.split(name, "/"))
  end

  defp application_spec(entries) do
    case Enum.find(entries, &application_entry?/1) do
      nil ->
        {:error, :no_application_metadata}

      %{data: data} when byte_size(data) > @max_application_entry_size ->
        {:error, :application_metadata_too_large}

      %{data: <<size::32, rest::binary>>} when byte_size(rest) >= size ->
        decode_application(binary_part(rest, 0, size))

      _ ->
        {:error, :malformed_application_metadata}
    end
  end

  defp decode_application(term) do
    case decode_term(term) do
      {:ok, {"application", name, properties}, _rest} when is_binary(name) and is_list(properties) ->
        {:ok, %{name: name, properties: properties}}

      {:ok, _other, _rest} ->
        {:error, :malformed_application_metadata}

      :error ->
        {:error, :malformed_application_metadata}
    end
  end

  defp fetch_property(properties, key) do
    case property(properties, key) do
      nil -> {:error, {:missing_application_property, key}}
      value -> {:ok, value}
    end
  end

  defp property(properties, key) do
    Enum.find_value(properties, fn
      {^key, value} when is_binary(value) -> value
      _ -> nil
    end)
  end

  @doc """
  Decode the subset of Erlang's external term format an application spec uses.

  Atoms are returned as strings. This exists so that reading an uploaded archive
  never adds to the atom table; see the "Terms" section above.
  """
  @spec decode_term(binary()) :: {:ok, term(), binary()} | :error
  def decode_term(<<131, rest::binary>>), do: term(rest)
  def decode_term(_), do: :error

  # SMALL_INTEGER_EXT / INTEGER_EXT
  defp term(<<97, value, rest::binary>>), do: {:ok, value, rest}
  defp term(<<98, value::signed-32, rest::binary>>), do: {:ok, value, rest}
  # ATOM_EXT / ATOM_UTF8_EXT / SMALL_ATOM_UTF8_EXT — returned as strings.
  defp term(<<100, length::16, atom::binary-size(length), rest::binary>>), do: {:ok, atom, rest}
  defp term(<<118, length::16, atom::binary-size(length), rest::binary>>), do: {:ok, atom, rest}
  defp term(<<119, length, atom::binary-size(length), rest::binary>>), do: {:ok, atom, rest}
  # NIL_EXT
  defp term(<<106, rest::binary>>), do: {:ok, [], rest}
  # STRING_EXT — a charlist, which for `vsn` and `description` is the string we
  # are after, so it is decoded straight to one.
  defp term(<<107, length::16, string::binary-size(length), rest::binary>>), do: {:ok, string, rest}
  # BINARY_EXT
  defp term(<<109, length::32, binary::binary-size(length), rest::binary>>), do: {:ok, binary, rest}
  # SMALL_TUPLE_EXT / LARGE_TUPLE_EXT
  defp term(<<104, arity, rest::binary>>), do: tuple(arity, rest)
  defp term(<<105, arity::32, rest::binary>>), do: tuple(arity, rest)
  # LIST_EXT
  defp term(<<108, count::32, rest::binary>>), do: list(count, rest)
  defp term(_), do: :error

  defp tuple(arity, binary) do
    case elements(arity, binary, []) do
      {:ok, items, rest} -> {:ok, List.to_tuple(items), rest}
      :error -> :error
    end
  end

  defp list(count, binary) do
    with {:ok, items, rest} <- elements(count, binary, []),
         # A proper list ends in NIL_EXT, which is a term like any other.
         {:ok, _tail, rest} <- term(rest) do
      {:ok, items, rest}
    end
  end

  defp elements(0, binary, acc), do: {:ok, Enum.reverse(acc), binary}

  defp elements(count, binary, acc) do
    case term(binary) do
      {:ok, item, rest} -> elements(count - 1, rest, [item | acc])
      :error -> :error
    end
  end

  @doc """
  Coerce an OTP application `vsn` into SemVer.

  `vsn` is free form — the compiler accepts anything, and `"1.2"` is common —
  while NervesHub requires strict SemVer. A leading `v` and a two part version
  are accepted; anything else is rejected with the raw value rather than coerced
  into a version that would sort wrongly.

  Deliberately narrower than `NervesHub.Firmwares.UpdateTool.EspIdf`'s, which
  also reads ESP's four part `1.2.3.4`. That shape means nothing here.
  """
  @spec normalise_version(String.t()) :: {:ok, String.t()} | {:error, {:invalid_version, String.t()}}
  def normalise_version(raw) when is_binary(raw) do
    stripped = raw |> String.trim() |> String.trim_leading("v") |> String.trim_leading("V")

    with :error <- parse_version(stripped),
         :error <- parse_version(two_part(stripped)) do
      {:error, {:invalid_version, raw}}
    end
  end

  def normalise_version(raw), do: {:error, {:invalid_version, inspect(raw)}}

  defp parse_version(nil), do: :error

  defp parse_version(candidate) do
    case Version.parse(candidate) do
      {:ok, _} -> {:ok, candidate}
      :error -> :error
    end
  end

  defp two_part(candidate) do
    case String.split(candidate, ".") do
      [_major, _minor] -> candidate <> ".0"
      _ -> nil
    end
  end

  # An unparseable hash is not fatal: `metadata_from_device/1` may still produce
  # a usable record, and a nil UUID only means the caller cannot fall back to a
  # database lookup.
  defp device_uuid(params) do
    with sha when is_binary(sha) <- params["atomvm_avm_sha256"],
         {:ok, raw} <- Base.decode16(sha, case: :mixed),
         true <- byte_size(raw) >= 16 do
      uuid_from_digest(raw)
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

  defp uuid_from_digest(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(6), _::binary>>
       ) do
    [a, b, c, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  defp download_archive(firmware) do
    {:ok, url} = firmware_upload_config().download_file(firmware)
    {:ok, archive_path} = Plug.Upload.random_file("downloaded_firmware_#{firmware.id}")

    case download(url, archive_path) do
      :ok -> {:ok, archive_path}
      error -> error
    end
  end

  defp firmware_upload_config(), do: Application.fetch_env!(:nerves_hub, :firmware_upload)

  defp download(url, filepath) do
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
