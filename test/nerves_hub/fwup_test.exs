defmodule NervesHub.FwupTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fwup
  alias NervesHub.Support.Fwup, as: SupportFwup
  alias NervesHub.Fixtures

  test "retrieves all fwup metadata", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    filepath = Fixtures.firmware_file_fixture(org_key, product, %{dir: tmp_dir})

    assert {:ok, metadata} = Fwup.metadata(filepath)

    assert "1.0.0" == metadata.version
    assert "D " == metadata.description
    assert "valid product" == metadata.product
    assert "me" == metadata.author
    assert is_binary(metadata.uuid)
    assert "x86_64" == metadata.architecture
    assert nil == metadata.vcs_identifier
    assert nil == metadata.misc
  end

  test "returns :invalid_metadata", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)

    SupportFwup.create_firmware_with_invalid_metadata(tmp_dir, "unsigned")
    {:ok, filepath} = SupportFwup.sign_firmware(tmp_dir, org_key.name, "unsigned", "signed")

    assert {:error, :invalid_metadata} == Fwup.metadata(filepath)
  end

  test "returns :invalid_fwup_file" do
    assert {:error, :invalid_fwup_file} == Fwup.metadata("/bob")
  end
end
