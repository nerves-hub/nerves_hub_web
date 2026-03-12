defmodule NervesHub.Accounts.RemoveAccountTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.RemoveAccount
  alias NervesHub.Fixtures

  test "remove_account for basic account", %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    Fixtures.deployment_group_fixture(firmware, %{user: user})

    RemoveAccount.remove_account(user.id)

    assert {:error, :not_found} = Accounts.get_user(user.id)
  end

  test "remove_account with org_users", %{tmp_dir: tmp_dir} do
    %{
      firmware: firmware1,
      user: user,
      org: org,
      org_key: org_key,
      product: product
    } = Fixtures.standard_fixture(tmp_dir)

    firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    Fixtures.firmware_delta_fixture(firmware1, firmware2)

    org2 = Fixtures.org_fixture(user, %{name: "Test-Org2"})

    {:ok, invite} =
      Accounts.add_or_invite_to_org(%{"email" => "test@test.org", "role" => "view"}, org2, user)

    params = %{"name" => "Test User Again", "password" => "Test-Password"}

    {:ok, org_user} = Accounts.create_user_from_invite(invite, org2, params)

    org2_key = Fixtures.org_key_fixture(org2, org_user.user, tmp_dir)
    org2_product = Fixtures.product_fixture(org_user.user, org2)
    org2_firmware = Fixtures.firmware_fixture(org2_key, org2_product, %{dir: tmp_dir})
    Fixtures.deployment_group_fixture(org2_firmware, %{user: user})

    firmware2 = Fixtures.firmware_fixture(org_key, product, %{dir: tmp_dir})
    Fixtures.firmware_delta_fixture(firmware1, firmware2)

    org3 = Fixtures.org_fixture(org_user.user, %{name: "org3"})
    org3_key = Fixtures.org_key_fixture(org3, org_user.user, tmp_dir)
    org3_product = Fixtures.product_fixture(org_user.user, org3)
    org3_firmware = Fixtures.firmware_fixture(org3_key, org3_product, %{dir: tmp_dir})
    Fixtures.deployment_group_fixture(org3_firmware, %{user: org_user.user})

    RemoveAccount.remove_account(user.id)

    assert {:error, _} = Accounts.get_user(user.id)
    assert {:error, _} = Accounts.get_org(org.id)
    assert {:ok, _} = Accounts.get_org(org2.id)
    assert {:ok, _} = Accounts.get_org(org3.id)
  end
end
