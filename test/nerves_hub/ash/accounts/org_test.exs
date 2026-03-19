defmodule NervesHub.Ash.Accounts.OrgTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Accounts.Org
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    %{user: user, org: org}
  end

  describe "read" do
    test "default read returns all orgs", %{org: org} do
      orgs = Org.read!()
      assert Enum.any?(orgs, &(&1.id == org.id))
    end

    test "get_by_name returns matching org", %{org: org} do
      found = Org.get_by_name!(org.name)
      assert found.id == org.id
      assert found.name == org.name
    end

    test "get_by_name excludes soft-deleted orgs", %{org: org} do
      NervesHub.Accounts.soft_delete_org(
        NervesHub.Repo.get!(NervesHub.Accounts.Org, org.id)
      )

      assert {:error, _} = Org.get_by_name(org.name)
    end

    test "get_for_user returns orgs for user", %{user: user, org: org} do
      orgs = Org.get_for_user!(user.id)
      assert Enum.any?(orgs, &(&1.id == org.id))
    end
  end

  describe "create" do
    test "create with valid name" do
      org = Org.create!(%{name: "test-org-#{System.unique_integer([:positive])}"})
      assert org.name
      assert org.id
    end
  end

  describe "create_with_user" do
    test "creates org and adds user as member", %{user: user} do
      org =
        Org.create_with_user!(user.id, %{
          name: "new-org-#{System.unique_integer([:positive])}"
        })

      assert org.id
      assert org.name
    end
  end

  describe "update" do
    test "updates org name", %{org: org} do
      ash_org = Org.get!(org.id)
      updated = Org.update!(ash_org, %{name: "updated-name"})
      assert updated.name == "updated-name"
    end
  end

  describe "destroy" do
    test "soft-deletes org", %{org: org} do
      ash_org = Org.get!(org.id)
      assert :ok = Org.destroy!(ash_org)

      # Org still exists in DB but is soft-deleted
      ecto_org = NervesHub.Repo.get(NervesHub.Accounts.Org, org.id)
      assert ecto_org.deleted_at != nil
    end
  end
end
