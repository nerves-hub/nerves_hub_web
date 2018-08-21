defmodule NervesHubWWWWeb.SessionControllerTest do
  use NervesHubWWWWeb.ConnCase

  alias NervesHubCore.{Accounts, Fixtures}

  setup do
    org = Fixtures.org_fixture(%{name: "my test org"})
    user = Fixtures.user_fixture(org, %{name: "Foo Bar", password: "password"})
    {:ok, %{user: user, org: org}}
  end

  describe "new session" do
    test "renders form", %{conn: conn} do
      conn = get(conn, session_path(conn, :new))
      assert html_response(conn, 200) =~ "Log in to your NervesHub account"
    end
  end

  describe "create session" do
    test "adds current_org_id to session", %{conn: conn, user: user, org: org} do
      Accounts.update_user(user, %{orgs: [%{name: "another org"}]})

      conn =
        post(
          conn,
          session_path(conn, :create),
          login: %{email: user.email, password: user.password}
        )

      assert redirected_to(conn) == dashboard_path(conn, :index)
      assert get_session(conn, "current_org_id") == org.id
    end
  end
end
