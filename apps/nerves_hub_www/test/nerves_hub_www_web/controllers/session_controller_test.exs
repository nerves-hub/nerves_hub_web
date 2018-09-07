defmodule NervesHubWWWWeb.SessionControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubCore.{Accounts, Fixtures}

  setup do
    org = Fixtures.org_fixture(%{name: "my test org 1"})

    user =
      Fixtures.user_fixture(%{
        orgs: [org],
        name: "Foo Bar",
        email: "foo@bar.com",
        password: "password"
      })

    {:ok, %{user: user, org: org}}
  end

  describe "new session" do
    test "renders form" do
      conn = build_conn()
      conn = get(conn, session_path(conn, :new))
      assert html_response(conn, 200) =~ "Log in to your NervesHub account"
    end
  end

  describe "create session" do
    test "adds current_org_id to session", %{user: user, org: org} do
      conn = build_conn()
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

  describe "set_org" do
    test "adds org to session if user belongs to org", %{conn: conn, current_user: user} do
      new_org = Fixtures.org_fixture(%{name: "this org"})
      {:ok, _user} = Accounts.add_user_to_org(user, new_org)

      result_conn = put(conn, session_path(conn, :set_org, org: new_org))

      assert redirected_to(result_conn) == dashboard_path(result_conn, :index)
      assert get_session(result_conn, "current_org_id") == new_org.id
    end

    test "does not add org to session if user does not belong to org", %{
      conn: conn,
      current_org: org
    } do
      new_org = Fixtures.org_fixture(%{name: "this org"})
      conn = put(conn, session_path(conn, :set_org, org: new_org))

      assert redirected_to(conn) == dashboard_path(conn, :index)
      assert get_session(conn, "current_org_id") == org.id
    end
  end
end
