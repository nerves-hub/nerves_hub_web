defmodule NervesHubWeb.SessionControllerTest do
  use NervesHubWeb.ConnCase.Browser, async: true

  alias NervesHub.Fixtures

  setup do
    user =
      Fixtures.user_fixture(%{
        name: "Foo Bar",
        email: "foo@bar.com",
        password: "password"
      })

    org = Fixtures.org_fixture(user, %{name: "my_test_org_1"})
    {:ok, %{user: user, org: org}}
  end

  describe "new session" do
    test "renders form" do
      conn = build_conn()
      conn = get(conn, Routes.session_path(conn, :new))
      assert html_response(conn, 200) =~ "Login"
    end
  end

  describe "create session" do
    test "redirected to product when logging in", %{user: user} do
      conn = build_conn()

      conn =
        post(
          conn,
          Routes.session_path(conn, :create),
          login: %{email_or_username: user.email, password: user.password}
        )

      assert redirected_to(conn) == Routes.home_path(conn, :index)
    end

    test "redirected to original URL when logging in", %{user: user} do
      conn =
        build_conn()
        |> get(~p"/orgs/new")
        |> post(
          ~p"/login",
          login: %{email_or_username: user.email, password: user.password}
        )

      assert redirected_to(conn) == ~p"/orgs/new"
    end
  end
end
