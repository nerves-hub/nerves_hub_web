defmodule NervesHubWebCore.Accounts.RemoveAccountTest do
  use NervesHubWebCore.DataCase, async: true

  alias NervesHubWebCore.{Accounts, Fixtures}

  test "remove_account for basic account" do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org)
    product = Fixtures.product_fixture(user, org)
    firmware = Fixtures.firmware_fixture(org_key, product)
    Fixtures.deployment_fixture(org, firmware)

    NervesHubWebCore.Accounts.RemoveAccount.remove_account(user.id)

    assert {:error, :not_found} = Accounts.get_user(user.id)
  end

  test "remove_account with org_users" do
    %{
      firmware: firmware1,
      user: user,
      org: org,
      org_key: org_key,
      product: product
    } = Fixtures.standard_fixture()

    firmware2 = Fixtures.firmware_fixture(org_key, product)
    Fixtures.firmware_delta_fixture(firmware1, firmware2)

    org2 = Fixtures.org_fixture(user, %{name: "Test-Org2"})
    {:ok, invite} = Accounts.add_or_invite_to_org(%{"email" => "test@test.org"}, org2)
    params = %{username: "Test-User2", password: "Test-Password"}
    {:ok, org_user} = Accounts.create_user_from_invite(invite, org2, params)

    org2_key = Fixtures.org_key_fixture(org2)
    org2_product = Fixtures.product_fixture(org_user.user, org2)
    org2_firmware = Fixtures.firmware_fixture(org2_key, org2_product)
    Fixtures.deployment_fixture(org, org2_firmware)

    firmware2 = Fixtures.firmware_fixture(org_key, product)
    Fixtures.firmware_delta_fixture(firmware1, firmware2)

    org3 = Fixtures.org_fixture(org_user.user, %{name: "org3"})
    org3_key = Fixtures.org_key_fixture(org3)
    org3_product = Fixtures.product_fixture(org_user.user, org3)
    org3_firmware = Fixtures.firmware_fixture(org3_key, org3_product)
    Fixtures.deployment_fixture(org, org3_firmware)

    NervesHubWebCore.Accounts.RemoveAccount.remove_account(user.id)

    assert {:error, _} = Accounts.get_user(user.id)
    assert {:error, _} = Accounts.get_org(org.id)
    assert {:ok, _} = Accounts.get_org(org2.id)
    assert {:ok, _} = Accounts.get_org(org3.id)
  end
end
