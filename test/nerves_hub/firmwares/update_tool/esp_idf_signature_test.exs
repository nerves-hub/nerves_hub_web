defmodule NervesHub.Firmwares.UpdateTool.EspIdfSignatureTest do
  @moduledoc """
  Secure Boot v2 signature verification.

  Every fixture here was produced by ESP-IDF's own `espsecure.py`, not by this
  repository. That matters more than usual: the block stores the RSA modulus and
  signature byte-reversed for the ESP32's RSA peripheral, and a hand-rolled
  signer written alongside the verifier would share any mistake about that and
  pass while production failed.

      espsecure.py generate_signing_key --version 2 --scheme rsa3072 signing_key.pem
      espsecure.py sign_data --version 2 --keyfile signing_key.pem \\
        --output signed_rsa3072.bin unsigned.bin
  """
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Firmwares.UpdateTool.EspIdf
  alias NervesHub.Fixtures

  @fixtures "test/fixtures/esp_idf"

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    {:ok, %{user: user, org: org}}
  end

  defp esp_key!(org, user, pem \\ nil) do
    pem = pem || File.read!("#{@fixtures}/signing_key_public.pem")

    {:ok, key} =
      Accounts.create_org_key(%{
        org_id: org.id,
        created_by_id: user.id,
        name: "esp-#{System.unique_integer([:positive])}",
        key: pem,
        scheme: :secure_boot_v2_rsa
      })

    key
  end

  defp signed(), do: "#{@fixtures}/signed_rsa3072.bin"

  defp tamper!(offset) do
    data = File.read!(signed())
    <<head::binary-size(^offset), byte, rest::binary>> = data
    path = Path.join(System.tmp_dir!(), "tampered-#{System.unique_integer([:positive])}.bin")
    File.write!(path, <<head::binary, Bitwise.bxor(byte, 0xFF), rest::binary>>)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "a genuinely signed image" do
    test "verifies against the registered key", %{org: org, user: user} do
      key = esp_key!(org, user)

      assert {:ok, matched} = EspIdf.verify_signature(signed(), [key])
      assert matched.id == key.id
    end

    test "is rejected when the org registered a different key", %{org: org, user: user} do
      # A second, unrelated RSA-3072 key.
      other =
        :public_key.generate_key({:rsa, 3072, 65_537})
        |> then(&:public_key.pem_entry_encode(:RSAPublicKey, rsa_public_from(&1)))
        |> List.wrap()
        |> :public_key.pem_encode()

      key = esp_key!(org, user, other)

      assert {:error, :invalid_signature} = EspIdf.verify_signature(signed(), [key])
    end

    test "is rejected when the org has no ESP keys at all", %{org: org, user: user} do
      # An Ed25519 fwup key is not a candidate — different scheme entirely.
      fwup_key = Fixtures.org_key_fixture(org, user)
      assert fwup_key.scheme == :ed25519

      assert {:error, :invalid_signature} = EspIdf.verify_signature(signed(), [fwup_key])
    end

    test "is rejected when the image body has been altered", %{org: org, user: user} do
      key = esp_key!(org, user)

      # Byte 64 is inside the image, well before the signature sector.
      assert {:error, :image_digest_mismatch} = EspIdf.verify_signature(tamper!(64), [key])
    end

    test "is rejected when the signature itself has been altered", %{org: org, user: user} do
      key = esp_key!(org, user)

      # Offset 4096 + 812 is the first byte of the signature field.
      assert {:error, :signature_block_corrupt} = EspIdf.verify_signature(tamper!(4096 + 812), [key])
    end
  end

  describe "an unsigned image" do
    test "is still accepted with no key recorded", %{org: org, user: user} do
      _key = esp_key!(org, user)

      assert {:ok, nil} = EspIdf.verify_signature("#{@fixtures}/unsigned.bin", [])
    end
  end

  # Erlang's generate_key returns a private key record; take the public half.
  defp rsa_public_from(private) do
    {:RSAPrivateKey, _v, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _o} = private
    {:RSAPublicKey, modulus, exponent}
  end
end
