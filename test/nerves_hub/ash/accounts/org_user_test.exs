defmodule NervesHub.Ash.Accounts.OrgUserTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Ash.Accounts.OrgUser
  alias NervesHub.Fixtures

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)
    %{user: user, org: org}
  end

  describe "read" do
    test "list_by_org returns org users", %{user: user, org: org} do
      org_users = OrgUser.list_by_org!(org.id)

      assert length(org_users) >= 1
      assert Enum.any?(org_users, &(&1.user_id == user.id))
    end

    test "get_by_org_and_user returns specific membership", %{user: user, org: org} do
      ou = OrgUser.get_by_org_and_user!(org.id, user.id)

      assert ou.user_id == user.id
      assert ou.org_id == org.id
    end

    test "list_admins_by_org returns admin users", %{org: org} do
      admins = OrgUser.list_admins_by_org!(org.id)

      assert length(admins) >= 1
      assert Enum.all?(admins, &(&1.role == :admin))
    end
  end

  describe "add_to_org" do
    test "adds user to org", %{org: org} do
      new_user = Fixtures.user_fixture()

      ou =
        OrgUser.add_to_org!(%{
          org_id: org.id,
          user_id: new_user.id,
          role: :view
        })

      assert ou.user_id == new_user.id
      assert ou.org_id == org.id
    end
  end

  describe "change_role" do
    test "changes role from admin to view", %{user: user, org: org} do
      # Add another admin first so we can change this one
      user2 = Fixtures.user_fixture()

      NervesHub.Accounts.add_org_user(
        NervesHub.Repo.get!(NervesHub.Accounts.Org, org.id),
        NervesHub.Repo.get!(NervesHub.Accounts.User, user2.id),
        %{role: :admin}
      )

      ou = OrgUser.get_by_org_and_user!(org.id, user.id)

      updated = OrgUser.change_role!(ou, :view)
      assert updated.role == :view
    end
  end

  describe "list_by_user" do
    test "returns memberships for user", %{user: user, org: org} do
      memberships = OrgUser.list_by_user!(user.id)
      assert Enum.any?(memberships, &(&1.org_id == org.id))
    end
  end

  describe "user_in_org" do
    test "returns true when user is in org", %{user: user, org: org} do
      assert OrgUser.user_in_org!(user.id, org.id) == true
    end

    test "returns false when user is not in org", %{user: user} do
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      assert OrgUser.user_in_org!(user.id, other_org.id) == false
    end
  end

  describe "has_role" do
    test "returns true when user has the specified role", %{user: user, org: org} do
      assert OrgUser.has_role!(org.id, user.id, :admin) == true
    end

    test "returns false when user is not in org" do
      user = Fixtures.user_fixture()
      other_user = Fixtures.user_fixture()
      other_org = Fixtures.org_fixture(other_user)
      assert OrgUser.has_role!(other_org.id, user.id, :admin) == false
    end
  end

  describe "remove_from_org" do
    test "removes user from org", %{org: org} do
      new_user = Fixtures.user_fixture()

      NervesHub.Accounts.add_org_user(
        NervesHub.Repo.get!(NervesHub.Accounts.Org, org.id),
        NervesHub.Repo.get!(NervesHub.Accounts.User, new_user.id),
        %{role: :view}
      )

      ou = OrgUser.get_by_org_and_user!(org.id, new_user.id)

      assert :ok = OrgUser.remove_from_org!(ou, org.id, new_user.id)
    end
  end
end
