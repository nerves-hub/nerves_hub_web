defmodule NervesHubWeb.Plugs.ServerAuthTest do
  use NervesHubWeb.ConnCase, async: true

  import Plug.Conn
  import Plug.Test

  alias NervesHub.Accounts.Scope
  alias NervesHub.Accounts.User
  alias NervesHubWeb.Plugs.ServerAuth

  describe "init/1" do
    test "returns opts unchanged" do
      assert ServerAuth.init([]) == []
    end
  end

  describe "call/2" do
    test "passes conn through when user has a server_role" do
      user = %User{server_role: :admin}
      scope = %Scope{user: user}

      conn =
        conn(:get, "/admin")
        |> assign(:current_scope, scope)

      result = ServerAuth.call(conn, [])
      refute result.halted
    end

    test "halts and redirects when user has no server_role" do
      user = %User{server_role: nil}
      scope = %Scope{user: user}

      conn =
        conn(:get, "/admin")
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_scope, scope)

      result = ServerAuth.call(conn, [])
      assert result.halted
    end
  end

  describe "resolve_user/1" do
    test "returns the user from current_scope" do
      user = %User{server_role: :admin}
      scope = %Scope{user: user}

      conn =
        conn(:get, "/")
        |> assign(:current_scope, scope)

      assert ServerAuth.resolve_user(conn) == user
    end
  end

  describe "resolve_access/1" do
    test "returns :all for admin role" do
      user = %User{server_role: :admin}
      assert ServerAuth.resolve_access(user) == :all
    end

    test "returns :read_only for non-admin role" do
      user = %User{server_role: :manage}
      assert ServerAuth.resolve_access(user) == :read_only
    end

    test "returns :read_only for nil server_role" do
      user = %User{server_role: nil}
      assert ServerAuth.resolve_access(user) == :read_only
    end
  end
end
