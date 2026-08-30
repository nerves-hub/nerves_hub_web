defmodule NervesHub.Firmwares.RaucUploadTest do
  @moduledoc """
  Uploading a real RAUC bundle, through the path an operator's upload takes.

  The unit tests next door cover the format in isolation. This covers the
  things only the whole path can be wrong about: that the tool is chosen from
  the bytes, that the signature is checked against a key the *organization*
  holds rather than one the test passed in, that the product's settings are
  honoured, and that what lands in the database is what was in the manifest.

  Not async: enabling the tool changes application environment, which is global.
  """

  use NervesHub.DataCase, async: false

  alias NervesHub.Firmwares
  alias NervesHub.Fixtures
  alias NervesHub.Products
  alias NervesHub.Support.RaucBundle

  @bundle Path.expand("../../fixtures/rauc/verity-1.13.raucb", __DIR__)
  @signer Path.expand("../../fixtures/rauc/signer-1.13.pem", __DIR__)

  setup do
    original = Application.get_env(:nerves_hub, :rauc_firmware_enabled)
    Application.put_env(:nerves_hub, :rauc_firmware_enabled, true)
    on_exit(fn -> Application.put_env(:nerves_hub, :rauc_firmware_enabled, original) end)

    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    # Named to match `[meta.nerveshub] product` in the fixture bundle. NervesHub
    # refuses a firmware whose declared product is not the one it was uploaded
    # to, and that check applies to RAUC exactly as it does to fwup.
    product = Fixtures.product_fixture(user, org, %{name: "Gateway"})

    %{user: user, org: org, product: product}
  end

  defp register_signer(org, user) do
    {:ok, org_key} =
      NervesHub.Accounts.create_org_key(%{
        org_id: org.id,
        created_by_id: user.id,
        name: "rauc-#{System.unique_integer([:positive])}",
        key: File.read!(@signer),
        scheme: :x509_certificate
      })

    org_key
  end

  defp allow_rauc(product) do
    {:ok, product} =
      Products.update_product(product, %{allowed_update_tools: ["fwup", "rauc"]})

    product
  end

  test "a signed bundle uploads and records what the manifest said", %{
    org: org,
    user: user,
    product: product
  } do
    org_key = register_signer(org, user)
    product = allow_rauc(product)

    assert {:ok, firmware} = Firmwares.create_firmware(org, @bundle, product: product)

    assert firmware.tool == "rauc"
    assert firmware.version == "1.4.2"
    assert firmware.platform == "acme-gateway"
    assert firmware.architecture == "aarch64"
    assert firmware.description == "built by rauc 1.13"

    # The declared product is checked against the one uploaded to rather than
    # stored — see the mismatch test below. What is stored is the association.
    assert firmware.product_id == product.id
    assert firmware.org_key_id == org_key.id

    # Kept for the tool that produced it, and nothing else reads them.
    assert firmware.tool_metadata["compatible"] == "acme-gateway"
    assert firmware.tool_metadata["bundle_format"] == "verity"

    # The digest RAUC itself computes over the manifest, which is what lets a
    # device recognise what it is running.
    assert firmware.uuid == "65547c89-8185-3d08-7e73-551be4c47401"
  end

  test "the tool is chosen from the bytes, not the file name", %{
    org: org,
    user: user,
    product: product
  } do
    _org_key = register_signer(org, user)
    product = allow_rauc(product)

    # A bundle uploaded under a name suggesting something else is still a
    # bundle. Nothing in the pipeline looks at the extension.
    misnamed = Path.join(System.tmp_dir!(), "definitely-a.fw")
    File.cp!(@bundle, misnamed)
    on_exit(fn -> File.rm(misnamed) end)

    assert {:ok, %{tool: "rauc"}} = Firmwares.create_firmware(org, misnamed, product: product)
  end

  test "a bundle built for another product is refused", %{
    org: org,
    user: user,
    product: product
  } do
    _org_key = register_signer(org, user)
    _ = allow_rauc(product)

    other = Fixtures.product_fixture(user, org, %{name: "SomethingElse"})
    other = allow_rauc(other)

    assert {:error, {:product_mismatch, "Gateway", "SomethingElse"}} =
             Firmwares.create_firmware(org, @bundle, product: other)
  end

  test "a product that does not accept rauc refuses the upload", %{
    org: org,
    user: user,
    product: product
  } do
    _org_key = register_signer(org, user)

    # Enabled on the instance, not enabled on this product.
    assert {:error, {:update_tool_not_allowed, "rauc", name}} =
             Firmwares.create_firmware(org, @bundle, product: product)

    assert name == product.name
  end

  test "an org with no certificate cannot accept a bundle", %{org: org, product: product} do
    product = allow_rauc(product)

    # The org may well hold fwup keys. None of them can anchor a CMS chain, and
    # trying each in turn would fail as a bad bundle rather than a missing key.
    assert {:error, :no_public_keys} = Firmwares.create_firmware(org, @bundle, product: product)
  end

  test "a bundle signed by somebody else is refused", %{org: org, user: user, product: product} do
    product = allow_rauc(product)

    stranger = RaucBundle.keypair("stranger")

    {:ok, _} =
      NervesHub.Accounts.create_org_key(%{
        org_id: org.id,
        created_by_id: user.id,
        name: "stranger-#{System.unique_integer([:positive])}",
        key: stranger.certificate,
        scheme: :x509_certificate
      })

    assert {:error, :invalid_signature} =
             Firmwares.create_firmware(org, @bundle, product: product)
  end

  test "the instance can refuse the format outright", %{org: org, user: user, product: product} do
    _org_key = register_signer(org, user)
    product = allow_rauc(product)

    Application.put_env(:nerves_hub, :rauc_firmware_enabled, false)

    # With the tool disabled the bytes are not recognised at all, which is the
    # point: turning it off stops uploads rather than merely hiding a checkbox.
    assert {:error, :unrecognised_firmware_format} =
             Firmwares.create_firmware(org, @bundle, product: product)
  end

  describe "the metadata path is never the trust decision" do
    # `extract_manifest/1` reads the manifest with `-noverify`, which skips the
    # signer's *chain*. That is only safe while every RAUC upload also goes
    # through `verify_signature/2` against a key the org holds — nothing in
    # `Firmwares` may excuse a RAUC bundle the way a product can excuse an
    # unsigned ESP-IDF image or packbeam.

    test "no product setting excuses an unverified bundle", %{
      org: org,
      user: user,
      product: product
    } do
      product = allow_rauc(product)

      # Both existing escape hatches, turned on at once. Neither names rauc, and
      # this is what stops one being added without anybody noticing that RAUC
      # metadata is read on a path with no chain verification.
      {:ok, product} =
        Products.update_product(product, %{
          allow_unsigned_esp_idf_firmware: true,
          allow_unsigned_atomvm_firmware: true
        })

      stranger = RaucBundle.keypair("stranger")

      {:ok, _} =
        NervesHub.Accounts.create_org_key(%{
          org_id: org.id,
          created_by_id: user.id,
          name: "stranger-#{System.unique_integer([:positive])}",
          key: stranger.certificate,
          scheme: :x509_certificate
        })

      assert {:error, :invalid_signature} =
               Firmwares.create_firmware(org, @bundle, product: product)
    end

    test "an org holding no certificate cannot upload one either", %{product: product, org: org} do
      product = allow_rauc(product)

      {:ok, product} =
        Products.update_product(product, %{
          allow_unsigned_esp_idf_firmware: true,
          allow_unsigned_atomvm_firmware: true
        })

      assert {:error, :no_public_keys} =
               Firmwares.create_firmware(org, @bundle, product: product)
    end
  end
end
