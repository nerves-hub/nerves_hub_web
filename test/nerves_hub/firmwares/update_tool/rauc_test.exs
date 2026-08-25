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

    test "a footer claiming an implausible size is refused", %{signer: signer} do
      # Reachable only above @max_signature_size (64 MiB) *and* within the file,
      # because `:signature_exceeds_bundle` is checked first — so the bundle has
      # to be genuinely enormous. Written sparse: one pwrite past a hole costs a
      # few blocks on disk rather than 64 MiB.
      path = Path.join(signer.dir, "enormous")
      max = 64 * 1024 * 1024
      size = max + 4096 + 8
      sigsize = max + 1

      {:ok, file} = File.open(path, [:write, :binary])
      :ok = :file.pwrite(file, size - 8, <<sigsize::unsigned-big-integer-size(64)>>)
      :ok = File.close(file)

      assert %{size: ^size} = File.stat!(path)
      assert {:error, :implausible_signature_size} = Rauc.read_signature(path)
    end

    test "each class of bad footer gets its own error", %{signer: signer} do
      # The order of these clauses is what makes `:truncated_bundle` unreachable
      # from file contents alone: every footer that would read off the end is
      # rejected before any read happens. Pinned here so a reordering shows up
      # as a failing test rather than as a read at a negative offset.
      payload = :binary.copy(<<0>>, 4096)

      footers = [
        {0, :no_signature},
        {4097, :signature_exceeds_bundle},
        {999_999, :signature_exceeds_bundle}
      ]

      for {sigsize, expected} <- footers do
        path = Path.join(signer.dir, "footer-#{sigsize}")
        File.write!(path, payload <> <<sigsize::unsigned-big-integer-size(64)>>)

        assert {:error, ^expected} = Rauc.read_signature(path),
               "footer claiming #{sigsize} bytes should be #{expected}"
      end

      # 4096 — the whole file bar the footer — is the largest claim that is
      # still in bounds, and it reads rather than being rejected. That is the
      # boundary the clause ordering turns on, so it is asserted rather than
      # inferred from the rejections above.
      exact = Path.join(signer.dir, "footer-exact")
      File.write!(exact, payload <> <<4096::unsigned-big-integer-size(64)>>)

      assert {:ok, ^payload} = Rauc.read_signature(exact)
    end
  end

  describe "openssl's error vocabulary" do
    test "still says \"no content\" for a detached signature", %{signer: signer, path: path} do
      # `classify/2` tells a plain bundle from a broken one by matching this
      # string, because the alternative is decoding the CMS ourselves to ask
      # whether it has an eContent. That is defensible only while the string
      # holds, so it is pinned against openssl directly rather than through
      # NervesHub — if this fails, openssl changed its wording and plain bundles
      # are about to start being reported as generic failures.
      RaucBundle.write(path, signer, detached: true)
      {:ok, signature} = Rauc.read_signature(path)

      cms_path = Path.join(signer.dir, "detached.der")
      File.write!(cms_path, signature)

      {output, status} =
        System.cmd(
          "openssl",
          ["cms", "-verify", "-inform", "DER", "-in", cms_path, "-out", Path.join(signer.dir, "out"), "-noverify"],
          stderr_to_stdout: true,
          env: []
        )

      assert status != 0
      assert output =~ "no content"
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

    test "a manifest altered inside the signature is refused", %{signer: signer, path: path} do
      RaucBundle.write(path, signer)

      original = File.read!(path)
      assert :binary.match(original, "version=1.4.2") != :nomatch

      # Same length, so every DER length in the CMS stays correct and the
      # structure still parses. What changes is the content the digest was
      # taken over.
      tampered = :binary.replace(original, "version=1.4.2", "version=9.9.9")
      assert byte_size(tampered) == byte_size(original)
      File.write!(path, tampered)

      # Metadata is read on a path with no keys to hand, so the signer's chain
      # is not checked here — but the signature over the content is, which is
      # what stops the manifest being edited after signing. Swapping `-verify`
      # for non-verifying extraction would pass every other test in this file.
      assert {:error, {:openssl_failed, status, output}} =
               Rauc.get_firmware_metadata_from_file(path)

      # Pinned to the *reason*, not merely to failure. Asserting only
      # `{:openssl_failed, _, _}` would pass just as happily if openssl fell
      # over for an unrelated reason, and tamper detection would quietly stop
      # being covered.
      assert status != 0
      assert output =~ "verify"
    end

    test "a bundle openssl cannot read reports openssl's own words", %{signer: signer} do
      # The bytes are a bundle by shape — squashfs magic and a footer pointing
      # at something the right size — but the signature is not a CMS structure
      # at all, so openssl fails for a reason NervesHub has no name for. That
      # reason has to survive as far as the caller.
      path = Path.join(signer.dir, "not-really-cms")
      junk = :binary.copy("x", 512)

      File.write!(
        path,
        "hsqs" <> :binary.copy(<<0>>, 4092) <> junk <> <<byte_size(junk)::unsigned-big-integer-size(64)>>
      )

      assert {:error, {:openssl_failed, status, output}} = Rauc.get_firmware_metadata_from_file(path)

      assert status != 0
      refute output == ""
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

    test "a repeated key takes the last value" do
      # GLib's key file, which is what a RAUC manifest is, says a later value
      # overrides an earlier one — so this is the value `rauc` itself would
      # read. Getting it backwards would have NervesHub and the device
      # disagreeing about `compatible`, which is what product and platform are
      # derived from.
      parsed =
        Rauc.parse_manifest("""
        [update]
        compatible=first
        compatible=second
        version=1.0.0
        """)

      assert parsed["update"]["compatible"] == "second"
      assert parsed["update"]["version"] == "1.0.0"
    end

    test "a repeated key in a section that already exists also takes the last value" do
      # The section is reopened, so the update goes through the merge branch
      # rather than the "first entry in a new section" branch.
      parsed =
        Rauc.parse_manifest("""
        [update]
        compatible=first

        [bundle]
        format=verity

        [update]
        compatible=second
        """)

      assert parsed["update"]["compatible"] == "second"
      assert parsed["bundle"]["format"] == "verity"
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

defmodule NervesHub.Firmwares.UpdateTool.RaucTrustScopeTest do
  @moduledoc """
  That an org's certificate is the *only* trust anchor for its bundles.

  `openssl cms -verify -CAfile ca.pem` reads as "trust exactly this", and it is
  not. `-CAfile` suppresses openssl's default CA *file*; the default CA
  *directory* and, on 3.x, the default CA *store* are still consulted. So a
  bundle whose signer chains to any root the host happens to trust verifies
  against an organization that never issued it.

  The rest of the suite cannot see this, because `RaucBundle.keypair/1` builds
  self-signed certificates. A self-signed stranger is in nobody's trust store,
  so it fails for the right reason by accident.
  """

  # Mutates `SSL_CERT_DIR` on the whole OS process, which every other openssl
  # child would inherit.
  use ExUnit.Case, async: false

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Firmwares.UpdateTool.Rauc
  alias NervesHub.Support.RaucBundle

  setup do
    authority = RaucBundle.ca_keypair()
    signer = RaucBundle.keypair_issued_by(authority)

    trusted_dir = RaucBundle.trust_as_system_root(authority.certificate)
    previous = System.get_env("SSL_CERT_DIR")
    System.put_env("SSL_CERT_DIR", trusted_dir)

    on_exit(fn ->
      if previous, do: System.put_env("SSL_CERT_DIR", previous), else: System.delete_env("SSL_CERT_DIR")
    end)

    path = Path.join(signer.dir, "bundle.raucb")
    RaucBundle.write(path, signer)

    %{authority: authority, signer: signer, path: path}
  end

  test "a signer trusted by the host is still not the org's signer", %{path: path} do
    # The org has its own, unrelated certificate registered. It did not issue
    # the bundle's signer and has nothing to do with the authority that did.
    stranger = RaucBundle.keypair("some-other-org")
    key = %OrgKey{name: "theirs", key: stranger.certificate, scheme: :x509_certificate}

    assert {:error, :invalid_signature} = Rauc.verify_signature(path, [key])
  end

  test "the org's own certificate still verifies its own bundle" do
    # The other half of the same fix: scoping trust must not break the case
    # NervesHub actually has, which is a self-signed certificate registered as
    # the org key.
    signer = RaucBundle.keypair("the-org")
    key = %OrgKey{name: "ours", key: signer.certificate, scheme: :x509_certificate}
    path = Path.join(signer.dir, "own.raucb")
    RaucBundle.write(path, signer)

    assert {:ok, ^key} = Rauc.verify_signature(path, [key])
  end

  test "an org that registered the issuing authority still verifies", %{
    authority: authority,
    path: path
  } do
    # Trust scoped to the org's keyring, not narrowed to self-signed leaves:
    # an org that registers the CA it issues from keeps working.
    key = %OrgKey{name: "ours", key: authority.certificate, scheme: :x509_certificate}

    assert {:ok, ^key} = Rauc.verify_signature(path, [key])
  end
end

defmodule NervesHub.Firmwares.UpdateTool.RaucRuntimeDependencyTest do
  @moduledoc """
  That a missing `openssl` is reported rather than raised.

  The shell-out is a runtime dependency nothing else in NervesHub has. The
  runtime image installs it, so this is not a live risk — but `System.cmd/3`
  raises when the executable is absent, and an `ErlangError` coming out of an
  upload reads as a bug in NervesHub rather than as a missing package.
  """

  # Mutates `PATH` on the whole OS process.
  use ExUnit.Case, async: false

  alias NervesHub.Firmwares.UpdateTool.Rauc
  alias NervesHub.Support.RaucBundle

  test "a missing openssl is an error, not a raise" do
    signer = RaucBundle.keypair()
    path = Path.join(signer.dir, "bundle.raucb")
    RaucBundle.write(path, signer)

    previous = System.get_env("PATH")
    on_exit(fn -> System.put_env("PATH", previous) end)

    # An empty path is the cheapest way to make openssl unfindable without
    # touching the machine the suite is running on.
    System.put_env("PATH", "")

    assert {:error, :openssl_not_available} = Rauc.extract_manifest(path)
    assert {:error, :openssl_not_available} = Rauc.get_firmware_metadata_from_file(path)
  end
end
