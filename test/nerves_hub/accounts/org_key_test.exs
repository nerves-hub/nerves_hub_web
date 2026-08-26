defmodule NervesHub.Accounts.OrgKeyTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts.OrgKey
  alias NervesHub.Support.EspIdf
  alias NervesHub.Support.Fwup

  describe "changeset/2" do
    @tag :tmp_dir
    test "valid ed25519 key produces a valid changeset", %{tmp_dir: tmp_dir} do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)
      Fwup.gen_key_pair("changeset_test", tmp_dir)
      pub_key = Fwup.get_public_key("changeset_test", tmp_dir)

      params = %{
        org_id: org.id,
        created_by_id: user.id,
        name: "test-key",
        key: pub_key,
        scheme: :ed25519
      }

      changeset = OrgKey.changeset(%OrgKey{}, params)
      assert changeset.valid?
    end

    test "invalid ed25519 key produces errors" do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)

      params = %{
        org_id: org.id,
        created_by_id: user.id,
        name: "bad-key",
        key: "not-valid-base64-key",
        scheme: :ed25519
      }

      changeset = OrgKey.changeset(%OrgKey{}, params)
      refute changeset.valid?
      assert changeset.errors[:key]
    end

    test "valid RSA-3072 key with secure_boot_v2_rsa scheme is accepted" do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)
      pem = EspIdf.signing_public_key()

      params = %{
        org_id: org.id,
        created_by_id: user.id,
        name: "esp-key",
        key: pem,
        scheme: :secure_boot_v2_rsa
      }

      changeset = OrgKey.changeset(%OrgKey{}, params)
      assert changeset.valid?
    end

    test "RSA key with wrong bit size is rejected" do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)

      # Build a minimal RSA 2048-bit public key PEM (not 3072-bit)
      {:RSAPrivateKey, _, modulus, pub_exp, _, _, _, _, _, _, _} =
        :public_key.generate_key({:rsa, 2048, 65_537})

      pub_key_record = {:RSAPublicKey, modulus, pub_exp}
      pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, pub_key_record)])

      params = %{
        org_id: org.id,
        created_by_id: user.id,
        name: "small-rsa",
        key: pem,
        scheme: :secure_boot_v2_rsa
      }

      changeset = OrgKey.changeset(%OrgKey{}, params)
      refute changeset.valid?
      assert changeset.errors[:key]
    end
  end

  describe "schemes/0" do
    test "returns the list of supported schemes" do
      assert [:ed25519, :secure_boot_v2_rsa, :x509_certificate] = OrgKey.schemes()
    end
  end

  describe "decode_rsa_public_key/1" do
    test "decodes a valid RSA PEM key" do
      pem = EspIdf.signing_public_key()

      assert {:ok, {:RSAPublicKey, _modulus, _exponent}} = OrgKey.decode_rsa_public_key(pem)
    end

    test "returns :error for a non-PEM binary" do
      assert :error = OrgKey.decode_rsa_public_key("not a pem")
    end

    test "returns :error for an empty binary" do
      assert :error = OrgKey.decode_rsa_public_key("")
    end

    test "returns :error for a non-binary" do
      assert :error = OrgKey.decode_rsa_public_key(nil)
      assert :error = OrgKey.decode_rsa_public_key(12_345)
    end

    test "returns :error for a PEM that is not an RSA key" do
      # A simple self-signed certificate PEM, not a bare RSA public key
      non_rsa_pem = """
      -----BEGIN CERTIFICATE-----
      MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
      -----END CERTIFICATE-----
      """

      assert :error = OrgKey.decode_rsa_public_key(non_rsa_pem)
    end
  end

  describe "update_changeset/2" do
    setup do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)
      org_key = NervesHub.Fixtures.org_key_fixture(org, user)

      {:ok, org_key: org_key}
    end

    test "allows updating name", %{org_key: org_key} do
      changeset = OrgKey.update_changeset(org_key, %{name: "new name"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "new name"
    end

    test "ignores org_id changes", %{org_key: org_key} do
      original_org_id = org_key.org_id
      changeset = OrgKey.update_changeset(org_key, %{org_id: original_org_id + 1})

      # org_id must not change
      refute Ecto.Changeset.get_change(changeset, :org_id)
    end

    test "validates key format on update", %{org_key: org_key} do
      changeset = OrgKey.update_changeset(org_key, %{key: "not-a-valid-key"})

      refute changeset.valid?
      assert changeset.errors[:key]
    end
  end

  describe "delete_changeset/2" do
    test "returns a changeset for the org_key" do
      user = NervesHub.Fixtures.user_fixture()
      org = NervesHub.Fixtures.org_fixture(user)
      org_key = NervesHub.Fixtures.org_key_fixture(org, user)

      changeset = OrgKey.delete_changeset(org_key, %{})

      assert changeset.data == org_key
    end
  end
end
