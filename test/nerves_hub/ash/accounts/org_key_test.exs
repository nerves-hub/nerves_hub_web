defmodule NervesHub.Ash.Accounts.OrgKeyTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Accounts.OrgKey
  alias NervesHub.Fixtures

  setup %{tmp_dir: tmp_dir} do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    org_key = Fixtures.org_key_fixture(org, user, tmp_dir)
    %{user: user, org: org, org_key: org_key}
  end

  describe "read" do
    test "list_by_org returns keys for org", %{org: org, org_key: org_key} do
      keys = OrgKey.list_by_org!(org.id)
      assert Enum.any?(keys, &(&1.id == org_key.id))
    end

    test "get_by_name finds key by org and name", %{org: org, org_key: org_key} do
      found = OrgKey.get_by_name!(org.id, org_key.name)
      assert found.id == org_key.id
    end
  end

  describe "create" do
    test "creates org key", %{org: org, user: user} do
      key =
        OrgKey.create!(%{
          name: "test-key-#{System.unique_integer([:positive])}",
          key: "fake-public-key-content",
          org_id: org.id,
          created_by_id: user.id
        })

      assert key.id
      assert key.org_id == org.id
    end
  end

  describe "destroy" do
    test "deletes org key", %{org_key: org_key} do
      ash_key = OrgKey.get!(org_key.id)
      assert :ok = OrgKey.destroy!(ash_key)
    end
  end
end
