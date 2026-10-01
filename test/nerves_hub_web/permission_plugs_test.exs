defmodule NervesHubWeb.PermissionPlugsTest do
  use NervesHub.DataCase, async: true

  import Plug.Test

  alias NervesHub.Accounts.Scope
  alias NervesHub.Fixtures
  alias NervesHubWeb.Helpers.PermissionPlugs

  setup do
    user = Fixtures.user_fixture()
    org = Fixtures.org_fixture(user)

    %{user: user, org: org}
  end

  defp conn_for(user, org, role) do
    scope =
      user
      |> Scope.for_user()
      |> Scope.put_org(org)
      |> Scope.put_role(role)

    Plug.Conn.assign(conn(:get, "/"), :current_scope, scope)
  end

  describe "require_permission/2" do
    test "lets through a built-in role that has the permission", %{user: user, org: org} do
      conn = conn_for(user, org, :manage)

      assert PermissionPlugs.require_permission(conn, :"firmware:upload") == conn
    end

    test "refuses a built-in role that doesn't", %{user: user, org: org} do
      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        PermissionPlugs.require_permission(conn_for(user, org, :view), :"firmware:upload")
      end
    end

    test "follows what a custom role grants", %{user: user, org: org} do
      role = Fixtures.org_role_fixture(org, %{permissions: ["firmware:upload"]})
      conn = conn_for(user, org, role)

      assert PermissionPlugs.require_permission(conn, :"firmware:upload") == conn

      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        PermissionPlugs.require_permission(conn, :"firmware:delete")
      end
    end

    test "refuses a scope with no org", %{user: user} do
      conn = Plug.Conn.assign(conn(:get, "/"), :current_scope, Scope.for_user(user))

      assert_raise NervesHubWeb.UnauthorizedError, fn ->
        PermissionPlugs.require_permission(conn, :"firmware:upload")
      end
    end
  end

  describe "require_membership/2" do
    test "lets through any member, whatever their role", %{user: user, org: org} do
      for role <- [:admin, :manage, :view, Fixtures.org_role_fixture(org)] do
        conn = conn_for(user, org, role)

        assert PermissionPlugs.require_membership(conn, []) == conn
      end
    end

    test "refuses a scope with no org or no role", %{user: user, org: org} do
      for scope <- [Scope.for_user(user), Scope.put_org(Scope.for_user(user), org)] do
        conn = Plug.Conn.assign(conn(:get, "/"), :current_scope, scope)

        assert_raise NervesHubWeb.UnauthorizedError, fn ->
          PermissionPlugs.require_membership(conn, [])
        end
      end
    end
  end
end
