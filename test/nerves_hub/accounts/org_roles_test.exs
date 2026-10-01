defmodule NervesHub.Accounts.OrgRolesTest do
  use NervesHub.DataCase, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.Invite
  alias NervesHub.Accounts.OrgRole
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Fixtures
  alias NervesHub.Repo

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    %{user: user, org: org}
  end

  describe "create_org_role/2" do
    test "saves the picked permissions, sorted and without blanks", %{org: org} do
      {:ok, role} =
        OrgRoles.create_org_role(org, %{
          "name" => " Release Manager ",
          "description" => "Ships firmware",
          "permissions" => ["", "firmware:upload", "deployment_group:update", "firmware:upload"]
        })

      assert role.name == "Release Manager"
      assert role.permissions == ["deployment_group:update", "firmware:upload"]
    end

    test "refuses a permission a custom role can't have", %{org: org} do
      {:error, changeset} = OrgRoles.create_org_role(org, %{"name" => "Sneaky", "permissions" => ["org_user:update"]})

      assert %{permissions: ["has an invalid entry"]} = errors_on(changeset)
    end

    test "refuses the name of a built-in role", %{org: org} do
      {:error, changeset} = OrgRoles.create_org_role(org, %{"name" => "Admin"})

      assert %{name: ["is the name of a built-in role"]} = errors_on(changeset)
    end

    test "refuses a name another of the org's roles has, whatever its case", %{org: org} do
      Fixtures.org_role_fixture(org, %{name: "Operators"})

      {:error, changeset} = OrgRoles.create_org_role(org, %{"name" => "operators"})

      assert %{name: ["is already used by another role"]} = errors_on(changeset)
    end

    test "lets another org use the same name", %{org: org, user: user} do
      Fixtures.org_role_fixture(org, %{name: "Operators"})
      other_org = Fixtures.org_fixture(user)

      assert {:ok, _role} = OrgRoles.create_org_role(other_org, %{"name" => "Operators"})
    end
  end

  describe "get_org_role/2" do
    test "only finds the org's own roles", %{org: org, user: user} do
      role = Fixtures.org_role_fixture(org)
      other_org = Fixtures.org_fixture(user)

      assert {:ok, %OrgRole{}} = OrgRoles.get_org_role(org, role.id)
      assert {:ok, %OrgRole{}} = OrgRoles.get_org_role(org, to_string(role.id))
      assert {:error, :not_found} = OrgRoles.get_org_role(other_org, role.id)
      assert {:error, :not_found} = OrgRoles.get_org_role(org, "admin")
    end
  end

  describe "delete_org_role/1" do
    test "deletes a role nobody uses, freeing its name", %{org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Temporary"})

      assert {:ok, _role} = OrgRoles.delete_org_role(role)
      assert OrgRoles.list_org_roles(org) == []
      assert {:ok, _role} = OrgRoles.create_org_role(org, %{"name" => "Temporary"})
    end

    test "refuses while a member holds the role", %{org: org} do
      role = Fixtures.org_role_fixture(org)
      {:ok, _org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})

      assert {:error, :in_use} = OrgRoles.delete_org_role(role)
    end

    test "allows it once the member has been removed", %{org: org} do
      role = Fixtures.org_role_fixture(org)
      member = Fixtures.user_fixture()
      {:ok, _org_user} = Accounts.add_org_user(org, member, %{org_role_id: role.id})
      :ok = Accounts.remove_org_user(org, member)

      assert {:ok, _role} = OrgRoles.delete_org_role(role)
    end

    test "refuses while an outstanding invite offers the role, even an expired one", %{org: org, user: user} do
      role = Fixtures.org_role_fixture(org)
      {:ok, invite} = Accounts.invite(%{"email" => "new@example.com", "org_role_id" => role.id}, org, user)

      expired_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)
      Repo.update_all(where(Invite, id: ^invite.id), set: [updated_at: expired_at])

      assert {:error, :in_use} = OrgRoles.delete_org_role(role)

      {:ok, _invite} = Accounts.decline_invite(invite)

      assert {:ok, _role} = OrgRoles.delete_org_role(role)
    end
  end

  test "member_counts/1 counts members by the role they hold", %{org: org} do
    role = Fixtures.org_role_fixture(org)
    {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})
    {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})
    {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})

    assert OrgRoles.member_counts(org) == %{:admin => 1, :view => 1, role.id => 2}
  end

  describe "giving members and invites a custom role" do
    test "a member can move between built-in and custom roles", %{org: org} do
      role = Fixtures.org_role_fixture(org)
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      {:ok, org_user} = Accounts.change_org_user_role(org_user, role)
      assert %{role: nil, org_role_id: role_id, org_role: %OrgRole{}} = org_user
      assert role_id == role.id

      {:ok, org_user} = Accounts.change_org_user_role(org_user, "manage")
      assert %{role: :manage, org_role_id: nil, org_role: nil} = org_user
    end

    test "another org's role is refused", %{org: org, user: user} do
      other_role = Fixtures.org_role_fixture(Fixtures.org_fixture(user))
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      assert {:error, changeset} = Accounts.change_org_user_role(org_user, other_role)
      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)

      assert {:error, changeset} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: other_role.id})
      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)
    end

    test "the database refuses another org's role too", %{org: org, user: user} do
      other_role = Fixtures.org_role_fixture(Fixtures.org_fixture(user))
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      assert_raise Postgrex.Error, ~r/foreign_key_violation/, fn ->
        Repo.update_all(where(Accounts.OrgUser, id: ^org_user.id), set: [role: nil, org_role_id: other_role.id])
      end
    end

    test "a deleted role is refused", %{org: org} do
      role = Fixtures.org_role_fixture(org)
      {:ok, _role} = OrgRoles.delete_org_role(role)
      {:ok, org_user} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view})

      assert {:error, changeset} = Accounts.change_org_user_role(org_user, role)
      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)
    end

    test "a member can't hold both kinds of role", %{org: org} do
      role = Fixtures.org_role_fixture(org)

      assert {:error, changeset} =
               Accounts.add_org_user(org, Fixtures.user_fixture(), %{role: :view, org_role_id: role.id})

      assert %{role: ["can't be both a built-in and a custom role"]} = errors_on(changeset)
    end

    test "accepting an invite for a custom role gives the member that role", %{org: org, user: user} do
      role = Fixtures.org_role_fixture(org)
      invitee = Fixtures.user_fixture()

      {:ok, invite} = Accounts.invite(%{"email" => invitee.email, "org_role_id" => role.id}, org, user)
      {:ok, org_user} = Accounts.accept_invite(invite, invitee)

      assert org_user.role == nil
      assert org_user.org_role_id == role.id
    end

    test "an invite for another org's role is refused", %{org: org, user: user} do
      other_role = Fixtures.org_role_fixture(Fixtures.org_fixture(user))

      assert {:error, changeset} =
               Accounts.invite(%{"email" => "new@example.com", "org_role_id" => other_role.id}, org, user)

      assert %{org_role_id: ["is not a role in this organization"]} = errors_on(changeset)
    end
  end
end
