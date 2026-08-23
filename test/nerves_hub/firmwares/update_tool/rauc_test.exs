defmodule NervesHub.Firmwares.UpdateTool.RaucTest do
  use ExUnit.Case, async: true

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.Rauc
  alias NervesHub.Support.RaucBundle

  setup do
    signer = RaucBundle.keypair()

    %{
      signer: signer,
      key: %OrgKey{name: "rauc", key: signer.certificate, scheme: :x509_certificate},
      path: Path.join(signer.dir, "bundle.raucb")
    }
  end

  describe "recognises?/1" do
    test "a bundle starts with the squashfs magic", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      assert Rauc.recognises?(path)
    end

    test "anything else is not ours", %{signer: signer} do
      other = Path.join(signer.dir, "not-a-bundle")
      File.write!(other, "PK\x03\x04 a zip, which is what fwup produces")

      refute Rauc.recognises?(other)
    end

    test "an unreadable path does not raise", %{signer: signer} do
      # Called against every configured tool on upload, so it has to survive
      # arbitrary input rather than take the whole upload down with it.
      refute Rauc.recognises?(Path.join(signer.dir, "does-not-exist"))
    end
  end

  describe "read_signature/1" do
    test "finds the signature using the footer", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      assert {:ok, signature} = Rauc.read_signature(path)
      # A DER SEQUENCE, which is what a CMS structure is.
      assert <<0x30, _::binary>> = signature
    end

    test "a file shorter than the footer is not a bundle", %{signer: signer} do
      path = Path.join(signer.dir, "stub")
      File.write!(path, "hsqs")

      assert {:error, :not_a_bundle} = Rauc.read_signature(path)
    end

    test "a signature larger than the bundle is refused", %{signer: signer} do
      path = Path.join(signer.dir, "lying-footer")
      File.write!(path, :binary.copy(<<0>>, 4096) <> <<999_999::unsigned-big-integer-size(64)>>)

      # Reading it would otherwise mean seeking to a negative offset.
      assert {:error, :signature_exceeds_bundle} = Rauc.read_signature(path)
    end

    test "a zero-length signature is refused", %{signer: signer} do
      path = Path.join(signer.dir, "unsigned")
      File.write!(path, :binary.copy(<<0>>, 4096) <> <<0::unsigned-big-integer-size(64)>>)

      assert {:error, :no_signature} = Rauc.read_signature(path)
    end
  end

  describe "verify_signature/2" do
    test "accepts a bundle the org's certificate signed", %{
      signer: signer,
      key: key,
      path: path
    } do
      RaucBundle.write(path, signer)

      assert {:ok, ^key} = Rauc.verify_signature(path, [key])
    end

    test "refuses one signed by somebody else", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      stranger = RaucBundle.keypair("someone-else")
      key = %OrgKey{name: "theirs", key: stranger.certificate, scheme: :x509_certificate}

      assert {:error, :invalid_signature} = Rauc.verify_signature(path, [key])
    end

    test "ignores keys belonging to other tools", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      # An org holding only fwup keys has no RAUC trust anchor. Handing an
      # Ed25519 key to openssl would fail as a bad bundle rather than as a
      # missing key.
      fwup_key = %OrgKey{name: "fwup", key: Base.encode64(:crypto.strong_rand_bytes(32))}

      assert {:error, :no_public_keys} = Rauc.verify_signature(path, [fwup_key])
    end

    test "finds the right key among several", %{signer: signer, key: key, path: path} do
      RaucBundle.write(path, signer)

      other = RaucBundle.keypair("other")
      wrong = %OrgKey{name: "wrong", key: other.certificate, scheme: :x509_certificate}

      assert {:ok, ^key} = Rauc.verify_signature(path, [wrong, key])
    end
  end

  describe "get_firmware_metadata_from_file/1" do
    test "reads the manifest out of the signature", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      assert {:ok, %{firmware_metadata: meta, tool: "rauc"}} =
               Rauc.get_firmware_metadata_from_file(path)

      assert meta.version == "1.4.2"
      assert meta.product == "Gateway"
      assert meta.architecture == "aarch64"
      assert meta.description == "a test bundle"
    end

    test "compatible stands in for platform and product", %{signer: signer, path: path} do
      manifest = RaucBundle.manifest(meta: [product: nil])
      RaucBundle.write(path, signer, manifest: manifest)

      assert {:ok, %{firmware_metadata: meta}} = Rauc.get_firmware_metadata_from_file(path)

      assert meta.platform == "acme-gateway"
      assert meta.product == "acme-gateway"
    end

    test "architecture has no default and says so", %{signer: signer, path: path} do
      manifest = RaucBundle.manifest(meta: [architecture: nil])
      RaucBundle.write(path, signer, manifest: manifest)

      # Guessing would send an arm64 bundle to an amd64 device, so the error
      # names the field rather than inventing one.
      assert {:error, {:missing_manifest_field, "[meta.nerveshub] architecture"}} =
               Rauc.get_firmware_metadata_from_file(path)
    end

    test "a missing version is refused", %{signer: signer, path: path} do
      manifest = RaucBundle.manifest(update: [version: nil])
      RaucBundle.write(path, signer, manifest: manifest)

      assert {:error, {:missing_manifest_field, "[update] version"}} =
               Rauc.get_firmware_metadata_from_file(path)
    end

    test "a plain bundle is refused with a reason", %{signer: signer, path: path} do
      RaucBundle.write(path, signer, detached: true)

      # The manifest is inside the squashfs rather than the signature, which
      # would mean unpacking a filesystem to read four lines of INI.
      assert {:error, :plain_bundle_unsupported} = Rauc.get_firmware_metadata_from_file(path)
    end
  end

  describe "uuid_from_manifest/1" do
    test "is stable for identical input", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)
      {:ok, %{firmware_metadata: first}} = Rauc.get_firmware_metadata_from_file(path)

      # A second signing produces a different CMS — different timestamps and a
      # different random — but the same manifest, so the same firmware.
      RaucBundle.write(path, signer)
      {:ok, %{firmware_metadata: second}} = Rauc.get_firmware_metadata_from_file(path)

      assert first.uuid == second.uuid
    end

    test "changes when the manifest does" do
      one = RaucBundle.manifest()
      two = RaucBundle.manifest(update: [version: "1.4.3"])

      refute Rauc.uuid_from_manifest(one) == Rauc.uuid_from_manifest(two)
    end

    test "looks like a uuid" do
      uuid = Rauc.uuid_from_manifest(RaucBundle.manifest())

      assert uuid =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    end
  end

  describe "parse_manifest/1" do
    test "reads sections, comments and values containing equals" do
      parsed =
        Rauc.parse_manifest("""
        # a comment
        [update]
        compatible=acme

        [meta.nerveshub]
        misc=a=b=c
        """)

      assert parsed["update"]["compatible"] == "acme"
      assert parsed["meta.nerveshub"]["misc"] == "a=b=c"
    end

    test "a key outside any section is ignored" do
      assert Rauc.parse_manifest("stray=value\n") == %{}
    end
  end

  describe "deltas" do
    test "are never generated for this format" do
      # The device fetches only the blocks it lacks, so a patch would cost
      # worker time and storage to produce something nothing asks for.
      refute Rauc.supports_deltas?()
      assert {:error, :deltas_not_supported} = Rauc.create_firmware_delta_file({"a", "b"}, {"c", "d"}, "/tmp")
    end
  end

  describe "device metadata" do
    test "is recognised by its own keys" do
      assert Rauc.recognises_device_metadata?(%{"rauc_compatible" => "acme-gateway"})
      refute Rauc.recognises_device_metadata?(%{"nerves_fw_uuid" => "abc"})
    end

    test "falls back to compatible for platform and product" do
      meta = Rauc.metadata_from_device(%{"rauc_compatible" => "acme", "rauc_version" => "1.0.0"})

      assert meta.platform == "acme"
      assert meta.product == "acme"
      assert meta.version == "1.0.0"
    end

    test "reads exactly what the agent sends on join" do
      # The keys here are the ones `nerves-hub-link-agent` puts in its join
      # payload for a RAUC device. They are a contract between two repositories,
      # so they are pinned here rather than left to be discovered when a device
      # joins and reports nothing.
      #
      # `rauc_architecture` is null on purpose: RAUC records no architecture
      # against a slot, so the device cannot know it and the server fills it in
      # from the firmware it matches by uuid.
      params = %{
        "update_tool" => "rauc",
        "device_api_version" => "2.2.0",
        "rauc_uuid" => "65547c89-8185-3d08-7e73-551be4c47401",
        "rauc_version" => "1.4.2",
        "rauc_platform" => "acme-gateway",
        "rauc_product" => "acme-gateway",
        "rauc_architecture" => nil,
        "rauc_compatible" => "acme-gateway",
        "rauc_tool_version" => "1.13"
      }

      assert Rauc.recognises_device_metadata?(params)

      meta = Rauc.metadata_from_device(params)

      assert meta.uuid == "65547c89-8185-3d08-7e73-551be4c47401"
      assert meta.version == "1.4.2"
      assert meta.platform == "acme-gateway"
      assert meta.architecture == nil
    end
  end
end

defmodule NervesHub.Firmwares.UpdateTool.RaucRealBundleTest do
  @moduledoc """
  Against a bundle `rauc` actually produced, rather than one assembled with
  openssl.

  The synthetic fixtures elsewhere in this suite let a test vary the manifest or
  corrupt the footer, which is most of what is worth testing. What they cannot
  tell you is whether the format was understood correctly in the first place —
  every one of them was built to the same reading of the spec that the parser
  was.
  """

  use ExUnit.Case, async: true

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.Rauc

  @bundle Path.expand("../../../fixtures/rauc/verity.raucb", __DIR__)
  @signer Path.expand("../../../fixtures/rauc/signer.pem", __DIR__)

  test "is recognised" do
    assert Rauc.recognises?(@bundle)
  end

  test "the footer locates a real CMS signature" do
    assert {:ok, <<0x30, _::binary>>} = Rauc.read_signature(@bundle)
  end

  test "verifies against the certificate that signed it" do
    key = %OrgKey{name: "rauc", key: File.read!(@signer), scheme: :x509_certificate}

    assert {:ok, ^key} = Rauc.verify_signature(@bundle, [key])
  end

  test "an old rauc drops the meta section, and the error says so" do
    # This fixture was built by RAUC 1.8 from a manifest that *did* contain
    # `[meta.nerveshub] architecture=aarch64`. Meta sections arrived in 1.9, and
    # older versions drop them while rewriting the manifest into the signature —
    # so the field is in the source manifest and not in the bundle.
    #
    # Reporting this as a missing field would send someone to look at a file
    # that already says `architecture=`.
    assert {:error, {:missing_manifest_section, "architecture"}} =
             Rauc.get_firmware_metadata_from_file(@bundle)
  end

  test "everything a 1.8 bundle does carry is read correctly" do
    {:ok, manifest} = Rauc.extract_manifest(@bundle)
    parsed = Rauc.parse_manifest(manifest)

    assert parsed["update"]["compatible"] == "acme-gateway"
    assert parsed["update"]["version"] == "1.4.2"
    assert parsed["image.rootfs"]["size"] == "65536"
  end

  test "the manifest rauc embedded carries the verity parameters" do
    {:ok, manifest} = Rauc.extract_manifest(@bundle)
    parsed = Rauc.parse_manifest(manifest)

    # rauc rewrites the manifest on the way into the signature, adding the root
    # hash and salt that make the payload verifiable block by block. That the
    # extracted manifest differs from the one handed to `rauc bundle` is the
    # reason the UUID is derived from what comes *out*.
    assert parsed["bundle"]["format"] == "verity"
    assert parsed["bundle"]["verity-hash"]
    assert parsed["bundle"]["verity-salt"]
  end
end

defmodule NervesHub.Firmwares.UpdateTool.RaucModernBundleTest do
  @moduledoc """
  Against a bundle built by RAUC 1.13, which preserves `[meta.*]`.

  The 1.8 fixture next door exercises what happens when it does not.
  """

  use ExUnit.Case, async: true

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.Rauc

  @bundle Path.expand("../../../fixtures/rauc/verity-1.13.raucb", __DIR__)
  @signer Path.expand("../../../fixtures/rauc/signer-1.13.pem", __DIR__)

  # What `rauc info --output-format=json` reports as "hash" for this bundle.
  @rauc_hash "65547c8981853d087e73551be4c474011fbde82a5eb34fca865e2c4822a2e144"

  test "verifies against the certificate that signed it" do
    key = %OrgKey{name: "rauc", key: File.read!(@signer), scheme: :x509_certificate}

    assert {:ok, ^key} = Rauc.verify_signature(@bundle, [key])
  end

  test "reads the metadata, including the meta section" do
    assert {:ok, %{firmware_metadata: meta, tool_metadata: tool_meta}} =
             Rauc.get_firmware_metadata_from_file(@bundle)

    assert meta.version == "1.4.2"
    assert meta.product == "Gateway"
    assert meta.architecture == "aarch64"
    assert meta.platform == "acme-gateway"
    assert meta.description == "built by rauc 1.13"
    assert tool_meta["compatible"] == "acme-gateway"
    assert tool_meta["bundle_format"] == "verity"
  end

  test "the uuid is derived from the digest RAUC itself computes" do
    # This is the property the whole metadata design rests on. RAUC records this
    # digest against the slot it installs into, so a device can read back what
    # it is running and reach the same UUID NervesHub holds — without NervesHub
    # having told it.
    #
    # If this ever fails, the device and the server have stopped agreeing about
    # what firmware is on the device, which no amount of care elsewhere fixes.
    {:ok, manifest} = Rauc.extract_manifest(@bundle)

    assert Base.encode16(:crypto.hash(:sha256, manifest), case: :lower) == @rauc_hash

    {:ok, %{firmware_metadata: meta}} = Rauc.get_firmware_metadata_from_file(@bundle)

    expected =
      @rauc_hash
      |> Base.decode16!(case: :lower)
      |> then(fn <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(6),
                   _::binary>> ->
        Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
      end)

    assert meta.uuid == expected
  end
end
