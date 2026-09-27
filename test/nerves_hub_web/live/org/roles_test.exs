defmodule NervesHubWeb.Live.Org.RolesTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Accounts
  alias NervesHub.Accounts.OrgRoles
  alias NervesHub.Accounts.Permissions
  alias NervesHub.Fixtures

  describe "index" do
    test "lists the built-in roles and the org's own, with how many hold each", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Release Manager", description: "Ships firmware"})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})

      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> assert_has("h1", text: "Roles")
      |> assert_has("#role-admin td", text: "Admin")
      |> assert_has("#role-manage td", text: "Manage")
      |> assert_has("#role-view td", text: "View")
      |> assert_has("#role-admin td", text: "1")
      |> assert_has("#role-#{role.id} td", text: "Release Manager")
      |> assert_has("#role-#{role.id} td", text: "Ships firmware")
      |> assert_has("#role-#{role.id} td", text: "1")
    end

    test "only offers built-in roles for viewing", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> refute_has("#role-admin a", text: "Edit")
      |> refute_has("#role-admin button", text: "Delete")
    end
  end

  describe "show" do
    test "a built-in role lists what it can and can't do", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles/view")
      |> assert_has("h1", text: "View")
      |> assert_has(~s(li[id="permission-support_script:run"] span[aria-label="Granted"]))
      |> assert_has(~s(li[id="permission-device:reboot"] span[aria-label="Not granted"]))
    end

    test "a custom role lists what was picked for it", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter", permissions: ["device:reboot"]})

      conn
      |> visit("/org/#{org.name}/settings/roles/#{role.id}")
      |> assert_has("h1", text: "Rebooter")
      |> assert_has(~s(li[id="permission-device:reboot"] span[aria-label="Granted"]))
      |> assert_has(~s(li[id="permission-device:view"] span[aria-label="Granted"]))
      |> assert_has(~s(li[id="permission-device:console"] span[aria-label="Not granted"]))
      |> assert_has(~s(li[id="permission-org_user:update"]), text: "Admin only")
    end

    test "another org's role isn't found", %{conn: conn, org: org, user: user} do
      other_role = Fixtures.org_role_fixture(Fixtures.org_fixture(user))

      assert_raise Ecto.NoResultsError, fn ->
        visit(conn, "/org/#{org.name}/settings/roles/#{other_role.id}")
      end
    end
  end

  describe "create" do
    test "with picked permissions", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> click_link("Add Role")
      |> assert_has("h1", text: "New Role")
      |> fill_in("Name", with: "Release Manager")
      |> fill_in("Description", with: "Ships firmware", exact: false)
      |> check("Upload firmware")
      |> check("Edit deployment groups and their releases")
      |> click_button("Create Role")
      |> assert_path("/org/#{org.name}/settings/roles")
      |> assert_has("div", text: "Role Release Manager created")
      |> assert_has("td", text: "Release Manager")

      assert [role] = OrgRoles.list_org_roles(org)
      assert role.description == "Ships firmware"
      assert role.permissions == ["deployment_group:update", "firmware:upload"]
    end

    test "copying a built-in role's permissions as a starting point", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles/new")
      |> refute_has("#copy_from_input option", text: "View")
      |> fill_in("Name", with: "Almost Manage")
      |> select("Copy permissions from", option: "Manage")
      |> uncheck("Open a device's remote console")
      |> click_button("Create Role")
      |> assert_has("div", text: "Role Almost Manage created")

      [role] = OrgRoles.list_org_roles(org)

      manage_options =
        for %{name: name, custom_roles: :optional, role: role} <- Permissions.all(),
            role in [:manage, :view],
            do: Atom.to_string(name)

      assert role.permissions == Enum.sort(manage_options -- ["device:console"])
    end

    test "copying another custom role's permissions", %{conn: conn, org: org} do
      Fixtures.org_role_fixture(org, %{
        name: "Release Manager",
        permissions: ["deployment_group:update", "firmware:upload"]
      })

      conn
      |> visit("/org/#{org.name}/settings/roles/new")
      |> fill_in("Name", with: "Release Manager with Console")
      |> select("Copy permissions from", option: "Release Manager")
      |> check("Open a device's remote console")
      |> click_button("Create Role")
      |> assert_has("div", text: "Role Release Manager with Console created")

      role = Enum.find(OrgRoles.list_org_roles(org), &(&1.name == "Release Manager with Console"))

      assert role.permissions == ["deployment_group:update", "device:console", "firmware:upload"]
    end

    test "shows what's wrong with the role", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles/new")
      |> fill_in("Name", with: "Admin")
      |> click_button("Create Role")
      |> assert_has("div", text: "is the name of a built-in role")

      assert OrgRoles.list_org_roles(org) == []
    end

    test "only offers permissions that are a choice", %{conn: conn, org: org} do
      conn
      |> visit("/org/#{org.name}/settings/roles/new")
      |> assert_has("label", text: "Open a device's remote console")
      # every member has these already
      |> refute_has("label", text: "View devices and stream their events")
      |> assert_has("p", text: "Every member can view the organization's products, devices and network identities.")
      # only the built-in admin role has these
      |> refute_has("label", text: "Change a member's role")
      |> refute_has("label", text: "Create custom roles")
    end
  end

  describe "edit" do
    test "changes the name and permissions", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter", permissions: ["device:reboot", "device:reconnect"]})

      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> within("#role-#{role.id}", &click_link(&1, "Edit"))
      |> assert_has("h1", text: "Edit Rebooter")
      |> fill_in("Name", with: "Restarter")
      |> uncheck("Reconnect devices")
      |> click_button("Save Role")
      |> assert_path("/org/#{org.name}/settings/roles")
      |> assert_has("div", text: "Role Restarter updated")

      assert {:ok, %{name: "Restarter", permissions: ["device:reboot"]}} = OrgRoles.get_org_role(org, role.id)
    end

    test "offers the org's other roles to copy from, but not the role itself", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter"})
      Fixtures.org_role_fixture(org, %{name: "Uploader"})

      conn
      |> visit("/org/#{org.name}/settings/roles/#{role.id}/edit")
      |> assert_has("#copy_from_input option", text: "Uploader")
      |> refute_has("#copy_from_input option", text: "Rebooter")
    end

    test "a built-in role can't be edited", %{conn: conn, org: org} do
      assert_raise Ecto.NoResultsError, fn ->
        visit(conn, "/org/#{org.name}/settings/roles/admin/edit")
      end
    end
  end

  describe "delete" do
    test "removes a role nobody holds", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Unused"})

      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> click_button("#delete-role-#{role.id}", "Delete")
      |> assert_has("div", text: "Role Unused deleted")
      |> refute_has("td", text: "Unused")
    end

    test "keeps a role someone holds", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Held"})
      {:ok, _} = Accounts.add_org_user(org, Fixtures.user_fixture(), %{org_role_id: role.id})

      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> click_button("#delete-role-#{role.id}", "Delete")
      |> assert_has("div", text: "This role is still in use")
      |> assert_has("td", text: "Held")
    end
  end

  describe "a member who isn't an admin" do
    setup %{org: org, user: user} do
      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, :manage)

      :ok
    end

    test "can look at roles but isn't offered changes", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org, %{name: "Rebooter"})

      conn
      |> visit("/org/#{org.name}/settings/roles")
      |> assert_has("td", text: "Rebooter")
      |> refute_has("a", text: "Add Role")
      |> refute_has("#role-#{role.id} a", text: "Edit")
      |> refute_has("#delete-role-#{role.id}")
    end

    test "can't create a role", %{conn: conn, org: org} do
      conn = visit(conn, "/org/#{org.name}/settings/roles/new")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_submit(conn.view, "save", %{"org_role" => %{"name" => "Mine"}}))

      assert OrgRoles.list_org_roles(org) == []
    end

    test "can't delete a role", %{conn: conn, org: org} do
      role = Fixtures.org_role_fixture(org)
      conn = visit(conn, "/org/#{org.name}/settings/roles")

      Process.flag(:trap_exit, true)

      assert {{%NervesHubWeb.UnauthorizedError{}, _}, _} =
               catch_exit(render_click(conn.view, "delete", %{"role_id" => role.id}))

      assert [_role] = OrgRoles.list_org_roles(org)
    end
  end

  describe "a member with a custom role" do
    test "can do what the role grants, and nothing else", %{conn: conn, org: org, user: user} do
      {:ok, org_user} = Accounts.get_org_user(org, user)
      role = Fixtures.org_role_fixture(org, %{permissions: ["signing_key:delete"]})
      {:ok, _} = Accounts.change_org_user_role(org_user, role)

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("button:not([disabled])", text: "Delete")
      |> visit("/org/#{org.name}/settings/roles")
      |> refute_has("a", text: "Add Role")

      {:ok, _} = OrgRoles.update_org_role(role, %{"permissions" => []})

      conn
      |> visit("/org/#{org.name}/settings/keys")
      |> assert_has("button[disabled]", text: "Delete")
    end

    test "sees the org's products", %{conn: conn, org: org, user: user, product: product} do
      {:ok, org_user} = Accounts.get_org_user(org, user)
      {:ok, _} = Accounts.change_org_user_role(org_user, Fixtures.org_role_fixture(org))

      conn
      |> visit("/org/#{org.name}")
      |> assert_has("a", text: product.name)
    end
  end
end
