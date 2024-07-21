defmodule NervesHub.FwupTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Fwup
  alias NervesHub.Fixtures

  test "retrieves all fwup metadata" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    filepath = Fixtures.firmware_file_fixture(org_key, product)

    assert {:ok, metadata} = Fwup.metadata(filepath)

    assert "1.0.0" == metadata[:version]
    assert "D " == metadata[:description]
    assert "valid product" == metadata[:product]
    assert "me" == metadata[:author]
    assert is_binary(metadata[:uuid])
    assert "x86_64" == metadata[:architecture]
    assert Map.has_key?(metadata, :vcs_identifier)
    assert nil == metadata[:vcs_identifier]
    assert Map.has_key?(metadata, :misc)
    assert nil == metadata[:misc]
  end

  test "returns :invalid_metadata" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    product = Fixtures.product_fixture(user, org)
    org_key = Fixtures.org_key_fixture(org, user)

    filepath = Fixtures.firmware_file_fixture(org_key, product, %{platform: nil})

    assert {:error, :invalid_metadata} == Fwup.metadata(filepath)
  end

  test "returns :invalid_fwup_file" do
    assert {:error, :invalid_fwup_file} == Fwup.metadata("/bob")
  end
end
